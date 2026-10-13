package com.attiv.flutter_log_file;

import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.Collections;
import java.util.zip.ZipInputStream;
import static org.junit.Assert.*;

public class LogArchiveTest {
    @Rule public TemporaryFolder temporary = new TemporaryFolder();

    @Test public void writesOriginalNamesAndBytesWithoutDeletingSources() throws Exception {
        File root = temporary.newFolder("logs");
        File first = new File(root, "custom-20261013.log");
        File second = new File(root, "custom-20261013.1.log");
        byte[] content = "日志\nfirst entry\n".getBytes(StandardCharsets.UTF_8);
        Files.write(first.toPath(), content);
        Files.write(second.toPath(), new byte[0]);
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        LogArchive.write(bytes, LogArchive.validate(root.getPath(), Arrays.asList(first.getPath(), second.getPath())));
        try (ZipInputStream zip = new ZipInputStream(new ByteArrayInputStream(bytes.toByteArray()))) {
            assertEquals(first.getName(), zip.getNextEntry().getName());
            assertArrayEquals(content, zip.readAllBytes());
            assertEquals(second.getName(), zip.getNextEntry().getName());
            assertEquals(0, zip.readAllBytes().length);
            assertNull(zip.getNextEntry());
        }
        assertArrayEquals(content, Files.readAllBytes(first.toPath()));
        assertTrue(second.exists());
    }

    @Test public void rejectsTraversalSymlinksDuplicatesAndMissingFiles() throws Exception {
        File root = temporary.newFolder("logs");
        File outside = temporary.newFile("secret.txt");
        File inside = new File(root, "app.txt");
        Files.write(inside.toPath(), "log".getBytes(StandardCharsets.UTF_8));
        assertThrows(IOException.class, () -> LogArchive.validate(root.getPath(), Collections.singletonList(outside.getPath())));
        assertThrows(IOException.class, () -> LogArchive.validate(root.getPath(), Collections.singletonList(new File(root, "../secret.txt").getPath())));
        File symlink = new File(root, "linked.txt");
        Files.createSymbolicLink(symlink.toPath(), outside.toPath());
        assertThrows(IOException.class, () -> LogArchive.validate(root.getPath(), Collections.singletonList(symlink.getPath())));
        assertThrows(IOException.class, () -> LogArchive.validate(root.getPath(), Arrays.asList(inside.getPath(), inside.getPath())));
        assertThrows(IOException.class, () -> LogArchive.validate(root.getPath(), Collections.singletonList(new File(root, "missing.txt").getPath())));
    }
}
