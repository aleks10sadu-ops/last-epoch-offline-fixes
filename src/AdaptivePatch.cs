using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;

namespace LastEpochOfflineFix {
    public sealed class PatchChange {
        public int offset;
        public string before, after;
    }
    public sealed class AdaptiveManifest {
        public int schema = 1, original_length, patched_length, exception_table_offset,
            exception_table_size, append_offset, append_alignment = 512;
        public string game_version = "unlisted-build", build = "adaptive-local",
            original_sha256, previous_patched_sha256 = new string('0', 64), patched_sha256,
            append_prefix_hex, exception_function_hex;
        public PatchChange[] changes;
        public bool adaptive = true;
    }
    public sealed class PortableImage {
        private sealed class Section {
            public int rva, virtualSize, raw, size, flags;
        }
        private readonly byte[] source;
        private readonly List<Section> sections = new List<Section>();
        private readonly Dictionary<int, int> functions = new Dictionary<int, int>();
        private readonly int pe, opt, sectionHeaders, sectionCount, tableRva, tableSize;
        public int ExceptionOffset { get; private set; }
        public int ExceptionSize { get { return tableSize; } }
        public int ImageSize { get; private set; }
        public static string Hash(byte[] bytes) {
            using (var sha = SHA256.Create()) { return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", ""); }
        }
        public static byte[] Hex(string text) {
            if (text == null || text.Length % 2 != 0) throw new Exception("Invalid hex data.");
            byte[] bytes = new byte[text.Length / 2];
            for (int i=0; i<bytes.Length; i++) bytes[i]=Convert.ToByte(text.Substring(i*2,2),16);
            return bytes;
        }
        private static string ToHex(byte[] bytes) { return BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant(); }
        private void Range(int start, int count) {
            if (start < 0 || count < 0 || (long)start + count > source.Length) throw new Exception("Invalid PE file range.");
        }
        private int I32(int p) { Range(p,4); return BitConverter.ToInt32(source,p); }
        private ushort U16(int p) { Range(p,2); return BitConverter.ToUInt16(source,p); }
        public PortableImage(byte[] bytes) {
            source = bytes;
            if (source.Length < 1024 || source.Length > 140*1024*1024 || U16(0)!=0x5a4d) throw new Exception("Unsupported PE image.");
            pe=I32(60); Range(pe,24);
            if (I32(pe)!=0x4550 || U16(pe+4)!=0x8664) throw new Exception("Only Windows x64 PE images are supported.");
            sectionCount=U16(pe+6); opt=pe+24;
            if (sectionCount<1 || sectionCount>=96 || U16(pe+20)<240 || U16(opt)!=0x20b) throw new Exception("Unsupported PE headers.");
            Range(opt,U16(pe+20)); sectionHeaders=opt+U16(pe+20); Range(sectionHeaders,(sectionCount+1)*40);
            if (I32(opt+32)!=4096 || I32(opt+36)!=512 || I32(opt+108)<16) throw new Exception("Unsupported PE alignment or directories.");
            if (I32(opt+144)!=0 || I32(opt+148)!=0) throw new Exception("Signed DLLs require manual review.");
            ImageSize=I32(opt+56);
            for (int i=0;i<sectionCount;i++) {
                int p=sectionHeaders+i*40;
                string name=Encoding.ASCII.GetString(source,p,8).TrimEnd('\0');
                if (name==".lefix") throw new Exception("This DLL already contains a patch section.");
                var s=new Section { virtualSize=I32(p+8),rva=I32(p+12),size=I32(p+16),raw=I32(p+20),flags=I32(p+36) };
                Range(s.raw,s.size);
                if (s.rva<0 || s.virtualSize<0 || s.rva%4096!=0 || s.raw%512!=0 || s.size%512!=0 ||
                    (long)s.rva+Math.Max(s.size,s.virtualSize)>ImageSize) throw new Exception("Invalid PE section layout.");
                foreach (var prior in sections) {
                    if (s.rva < (long)prior.rva+Math.Max(prior.size,prior.virtualSize) && prior.rva < (long)s.rva+Math.Max(s.size,s.virtualSize)) throw new Exception("Overlapping virtual sections.");
                    if (s.size>0 && prior.size>0 && s.raw<(long)prior.raw+prior.size && prior.raw<(long)s.raw+s.size) throw new Exception("Overlapping file sections.");
                }
                sections.Add(s);
            }
            tableRva=I32(opt+136); tableSize=I32(opt+140);
            if (tableSize<=0 || tableSize%12!=0) throw new Exception("Invalid exception table.");
            ExceptionOffset=Offset(tableRva,tableSize); int previous=-1;
            for (int p=ExceptionOffset;p<ExceptionOffset+tableSize;p+=12) {
                int begin=I32(p),end=I32(p+4),unwind=I32(p+8);
                if (begin<=previous || end<=begin || !Executable(begin,end-begin)) throw new Exception("Invalid runtime function.");
                Offset(unwind,4); functions.Add(begin,end-begin); previous=begin;
            }
        }
        public int Offset(int rva,int count) {
            if (rva<0 || count<0) throw new Exception("Invalid RVA.");
            foreach (var s in sections) if (rva>=s.rva && (long)rva+count<=(long)s.rva+s.size) {
                int p=checked(s.raw+rva-s.rva); Range(p,count); return p;
            }
            throw new Exception("RVA is outside file-backed sections.");
        }
        public bool Executable(int rva,int count) {
            foreach (var s in sections) if (rva>=s.rva && (long)rva+count<=(long)s.rva+s.size && (s.flags&0x20000000)!=0) return true;
            return false;
        }
        public void WritableSlot(int rva) {
            Offset(rva,8);
            foreach (var s in sections) if (rva>=s.rva && (long)rva+8<=(long)s.rva+s.size &&
                (s.flags&unchecked((int)0x80000000))!=0 && (s.flags&0x20000000)==0 && rva%8==0) return;
            throw new Exception("Stock identity reference is not a writable data slot.");
        }
        public int FindFunction(string name,int length,byte[] anchor,int anchorOffset,int[] masks,string expected) {
            if (length<=0 || anchor.Length<8 || anchorOffset<0 || anchorOffset+anchor.Length>length || masks.Length%2!=0) throw new Exception("Invalid function template.");
            int result=-1, matches=0;
            foreach (var f in functions) {
                if (f.Value!=length) continue;
                int start=Offset(f.Key,length); bool equal=true;
                for (int i=0;i<anchor.Length;i++) if (source[start+anchorOffset+i]!=anchor[i]) { equal=false;break; }
                if (!equal) continue;
                byte[] normalized=new byte[length]; Array.Copy(source,start,normalized,0,length);
                for (int i=0;i<masks.Length;i+=2) {
                    if (masks[i]<0 || masks[i+1]<1 || masks[i]+masks[i+1]>length) throw new Exception("Invalid normalized range.");
                    Array.Clear(normalized,masks[i],masks[i+1]);
                }
                if (Hash(normalized)!=expected) continue;
                result=f.Key;matches++;
            }
            if (matches!=1) throw new Exception("Adaptive match refused for "+name+": expected 1 exact function, found "+matches+".");
            return result;
        }
        public int Relative(int function,int displacement,int width,int next) {
            int length;
            if (!functions.TryGetValue(function,out length) || displacement<0 || next<=0 || next>length ||
                (width!=1 && width!=4) || displacement+width>length) throw new Exception("Invalid relative reference.");
            int p=Offset(function+displacement,width);
            int delta=width==1 ? unchecked((sbyte)source[p]) : I32(p);
            return checked(function+next+delta);
        }
        public int Export(string wanted) {
            int rva=I32(opt+112),size=I32(opt+116),p=Offset(rva,40);
            int count=I32(p+20),names=I32(p+24);
            if (count<1 || count>100000 || names<1 || names>count) throw new Exception("Invalid exports.");
            int addr=Offset(I32(p+28),checked(count*4)),name=Offset(I32(p+32),checked(names*4)),ord=Offset(I32(p+36),checked(names*2));
            for (int i=0;i<names;i++) {
                int nameRva=I32(name+i*4);var chars=new List<byte>();
                for(int j=0;j<256;j++) { byte b=source[Offset(nameRva+j,1)];if(b==0)break;chars.Add(b); }
                if (Encoding.ASCII.GetString(chars.ToArray())!=wanted) continue;
                int index=U16(ord+i*2);if(index>=count) throw new Exception("Invalid export ordinal.");
                int result=I32(addr+index*4);
                if ((result>=rva && (long)result<(long)rva+size) || !Executable(result,1)) throw new Exception("Unsupported export target.");
                return result;
            }
            throw new Exception("Required IL2CPP export not found: "+wanted);
        }
        public void Branch(int site,int expected) {
            int p=Offset(site,6);
            if (source[p]!=0x0f || source[p+1]!=0x84 || checked(site+6+I32(p+2))!=expected) throw new Exception("Changed cache branch.");
        }
        public int SectionRva() {
            int end=0;foreach(var s in sections)end=Math.Max(end,checked(s.rva+Math.Max(s.size,s.virtualSize)));
            return checked((end+4095)/4096*4096);
        }
        public void SetRelative(byte[] data,int displacement,int next,int wrapper,int target) {
            if(displacement<0 || displacement+4>data.Length)throw new Exception("Invalid wrapper reference.");
            Array.Copy(BitConverter.GetBytes(checked(target-wrapper-next)),0,data,displacement,4);
        }
        private static byte[] Number(int n) { return BitConverter.GetBytes(n); }
        private static void Write32(byte[] bytes,int p,int n) { Array.Copy(Number(n),0,bytes,p,4); }
        private static void Change(byte[] original,byte[] output,List<PatchChange> changes,int offset,byte[] value) {
            byte[] before=new byte[value.Length];Array.Copy(original,offset,before,0,value.Length);
            changes.Add(new PatchChange{offset=offset,before=ToHex(before),after=ToHex(value)});
            Array.Copy(value,0,output,offset,value.Length);
        }
        public AdaptiveManifest Build(byte[] prefix,int callSite,int[] branches,int empty,int codeSize,int unwindOffset) {
            if(prefix.Length!=192 || codeSize!=175 || unwindOffset!=184 || branches.Length!=2 || source.Length%512!=0) throw new Exception("Unsupported patch layout.");
            int section=SectionRva(),header=sectionHeaders+sectionCount*40;
            int firstRaw=int.MaxValue;foreach(var s in sections)if(s.size>0)firstRaw=Math.Min(firstRaw,s.raw);
            if(header+40>Math.Min(I32(opt+60),firstRaw))throw new Exception("No free PE section header.");
            for(int i=0;i<40;i++)if(source[header+i]!=0)throw new Exception("PE section header slot is occupied.");
            int virtualSize=checked(prefix.Length+tableSize+12),rawSize=checked((virtualSize+511)/512*512),length=checked(source.Length+rawSize);
            if(length>150*1024*1024)throw new Exception("Patched DLL is too large.");
            var output=new byte[length];Array.Copy(source,output,source.Length);Array.Copy(prefix,0,output,source.Length,prefix.Length);
            Array.Copy(source,ExceptionOffset,output,source.Length+prefix.Length,tableSize);
            byte[] entry=new byte[12];Write32(entry,0,section);Write32(entry,4,section+codeSize);Write32(entry,8,section+unwindOffset);
            Array.Copy(entry,0,output,source.Length+prefix.Length+tableSize,12);
            var changes=new List<PatchChange>();
            int call=Offset(callSite,5);if(source[call]!=0xe8)throw new Exception("Changed offline constructor call.");
            byte[] jump=new byte[5];jump[0]=0xe8;Write32(jump,1,checked(section-callSite-5));Change(source,output,changes,call,jump);
            foreach(int branch in branches){byte[] j=new byte[6];j[0]=0x0f;j[1]=0x84;Write32(j,2,checked(empty-branch-6));Change(source,output,changes,Offset(branch,6),j);}
            byte[] newHeader=new byte[40];Array.Copy(Encoding.ASCII.GetBytes(".lefix"),newHeader,6);
            Write32(newHeader,8,virtualSize);Write32(newHeader,12,section);Write32(newHeader,16,rawSize);Write32(newHeader,20,source.Length);Write32(newHeader,36,0x60000020);
            Change(source,output,changes,header,newHeader);Change(source,output,changes,pe+6,BitConverter.GetBytes((ushort)(sectionCount+1)));
            Change(source,output,changes,opt+56,Number(checked((section+virtualSize+4095)/4096*4096)));
            Change(source,output,changes,opt+4,Number(checked(I32(opt+4)+rawSize)));
            Change(source,output,changes,opt+136,Number(section+prefix.Length));Change(source,output,changes,opt+140,Number(tableSize+12));
            ulong sum=0;
            for(int i=0;i<output.Length;i+=2){if(i==opt+64 || i==opt+66)continue;sum+=(ushort)(output[i]|output[i+1]<<8);sum=(sum&0xffff)+(sum>>16);}
            sum=(sum&0xffff)+(sum>>16);sum=(sum&0xffff)+(sum>>16);sum+= (uint)output.Length;
            Change(source,output,changes,opt+64,Number((int)sum));
            return new AdaptiveManifest {original_length=source.Length,patched_length=output.Length,original_sha256=Hash(source),patched_sha256=Hash(output),
                exception_table_offset=ExceptionOffset,exception_table_size=tableSize,append_offset=source.Length,
                append_prefix_hex=ToHex(prefix),exception_function_hex=ToHex(entry),changes=changes.ToArray()};
        }
    }
}
