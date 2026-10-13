package com.attiv.flutter_log_file;

import android.app.Activity;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.DocumentsContract;
import android.provider.MediaStore;
import java.io.File;
import java.io.IOException;
import java.io.OutputStream;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/** Android Downloads export, registered automatically by Flutter. */
public final class FlutterLogFilePlugin implements FlutterPlugin, ActivityAware,
        MethodChannel.MethodCallHandler, PluginRegistry.ActivityResultListener {
    private static final int REQUEST_SAVE_LOGS = 7109;
    private final Handler main = new Handler(Looper.getMainLooper());
    private Context context;
    private MethodChannel channel;
    private ExecutorService worker;
    private ActivityPluginBinding activityBinding;
    private MethodChannel.Result pendingResult;
    private List<File> pendingFiles;

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        worker = Executors.newSingleThreadExecutor();
        channel = new MethodChannel(binding.getBinaryMessenger(), "flutter_log_file/downloads");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        if (!call.method.equals("exportLogsToDownloads")) {
            result.notImplemented();
            return;
        }
        if (pendingResult != null) {
            result.error("busy", "A log export is already in progress", null);
            return;
        }
        try {
            List<File> files = LogArchive.validate(call.argument("directory"), call.argument("paths"));
            String name = "logs-" + new SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(new Date())
                    + "-" + UUID.randomUUID().toString().substring(0, 8) + ".zip";
            pendingResult = result;
            pendingFiles = files;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                export(result, () -> saveToDownloads(files, name));
            } else {
                if (activityBinding == null) throw new IOException("Open the app to choose where to save logs");
                Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
                intent.addCategory(Intent.CATEGORY_OPENABLE);
                intent.setType("application/zip");
                intent.putExtra(Intent.EXTRA_TITLE, name);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI,
                            Uri.parse("content://com.android.providers.downloads.documents/root/downloads"));
                }
                activityBinding.getActivity().startActivityForResult(intent, REQUEST_SAVE_LOGS);
            }
        } catch (Exception error) {
            clearPending();
            result.error("export_failed", error.getMessage(), null);
        }
    }

    @Override
    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != REQUEST_SAVE_LOGS || pendingResult == null) return false;
        MethodChannel.Result result = pendingResult;
        if (resultCode != Activity.RESULT_OK) {
            clearPending();
            result.success(null);
            return true;
        }
        Uri uri = data == null ? null : data.getData();
        if (uri == null) {
            clearPending();
            result.error("export_failed", "The save picker did not return a file", null);
            return true;
        }
        List<File> files = pendingFiles;
        export(result, () -> {
            try {
                OutputStream output = context.getContentResolver().openOutputStream(uri, "w");
                if (output == null) throw new IOException("Could not open the selected file");
                LogArchive.write(output, files);
                return uri.toString();
            } catch (Exception error) {
                try { DocumentsContract.deleteDocument(context.getContentResolver(), uri); }
                catch (Exception ignored) { /* Keep the original failure. */ }
                throw error;
            }
        });
        return true;
    }

    @android.annotation.TargetApi(Build.VERSION_CODES.Q)
    private String saveToDownloads(List<File> files, String name) throws Exception {
        ContentValues values = new ContentValues();
        values.put(MediaStore.Downloads.DISPLAY_NAME, name);
        values.put(MediaStore.Downloads.MIME_TYPE, "application/zip");
        values.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
        values.put(MediaStore.Downloads.IS_PENDING, 1);
        Uri uri = context.getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
        if (uri == null) throw new IOException("Could not create a file in Downloads");
        try {
            OutputStream output = context.getContentResolver().openOutputStream(uri, "w");
            if (output == null) throw new IOException("Could not write to Downloads");
            LogArchive.write(output, files);
            values.clear();
            values.put(MediaStore.Downloads.IS_PENDING, 0);
            if (context.getContentResolver().update(uri, values, null, null) != 1) {
                throw new IOException("Could not finish saving to Downloads");
            }
        } catch (Exception error) {
            try { context.getContentResolver().delete(uri, null, null); }
            catch (Exception ignored) { /* Keep the original failure. */ }
            throw error;
        }
        return Environment.DIRECTORY_DOWNLOADS + "/" + name;
    }

    private interface ExportTask { String save() throws Exception; }

    private void export(MethodChannel.Result result, ExportTask task) {
        worker.execute(() -> {
            try {
                String location = task.save();
                main.post(() -> {
                    if (pendingResult == result) {
                        clearPending();
                        result.success(location);
                    }
                });
            } catch (Exception error) {
                main.post(() -> {
                    if (pendingResult == result) {
                        clearPending();
                        result.error("export_failed", error.getMessage(), null);
                    }
                });
            }
        });
    }

    private void clearPending() { pendingResult = null; pendingFiles = null; }

    @Override
    public void onAttachedToActivity(ActivityPluginBinding binding) {
        activityBinding = binding;
        binding.addActivityResultListener(this);
    }

    @Override
    public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() { detachActivity(); }

    @Override
    public void onDetachedFromActivity() {
        detachActivity();
        cancelPending();
    }

    private void detachActivity() {
        if (activityBinding != null) activityBinding.removeActivityResultListener(this);
        activityBinding = null;
    }

    private void cancelPending() {
        if (pendingResult != null) pendingResult.error("export_interrupted", "Export interrupted; please retry", null);
        clearPending();
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        detachActivity();
        cancelPending();
        worker.shutdownNow();
    }
}
