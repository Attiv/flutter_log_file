package com.attiv.flutter_log_file;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

final class LogArchive {
    static List<File> validate(String directory, List<String> paths) throws IOException {
        if (directory == null || paths == null || paths.isEmpty()) {
            throw new IOException("No log files to save");
        }
        File root = new File(directory).getCanonicalFile();
        List<File> files = new ArrayList<>();
        Set<String> names = new HashSet<>();
        for (String path : paths) {
            File file = new File(path).getCanonicalFile();
            if (!root.equals(file.getParentFile()) || !file.isFile() || !names.add(file.getName())) {
                throw new IOException("Invalid log file");
            }
            files.add(file);
        }
        return files;
    }

    static void write(OutputStream output, List<File> files) throws IOException {
        try (ZipOutputStream zip = new ZipOutputStream(output)) {
            byte[] buffer = new byte[64 * 1024];
            for (File file : files) {
                ZipEntry entry = new ZipEntry(file.getName());
                entry.setTime(file.lastModified());
                zip.putNextEntry(entry);
                // Bound the snapshot even if the active log keeps growing.
                long remaining = file.length();
                try (InputStream input = new java.io.FileInputStream(file)) {
                    while (remaining > 0) {
                        if (Thread.currentThread().isInterrupted()) {
                            throw new IOException("Export interrupted; please retry");
                        }
                        int count = input.read(buffer, 0, (int) Math.min(buffer.length, remaining));
                        if (count < 0) throw new IOException("Log changed during export; please retry");
                        zip.write(buffer, 0, count);
                        remaining -= count;
                    }
                }
                zip.closeEntry();
            }
        }
    }
}
