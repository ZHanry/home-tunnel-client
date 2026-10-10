using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class NestLinkInstallPaths
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern uint GetFinalPathNameByHandle(IntPtr file, StringBuilder path, uint size, uint flags);

    public static string ActualFilePath(string path)
    {
        using (var file = File.Open(path, FileMode.Open, FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete))
        {
            var result = new StringBuilder(32768);
            uint length = GetFinalPathNameByHandle(file.SafeFileHandle.DangerousGetHandle(), result, 32768, 0);
            if (length == 0 || length >= 32768) throw new Win32Exception(Marshal.GetLastWin32Error());
            string value = result.ToString();
            return value.StartsWith(@"\\?\") ? value.Substring(4) : value;
        }
    }
}
