import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const FileToolsApp());

class FileToolsApp extends StatefulWidget {
  const FileToolsApp({super.key});
  @override
  State<FileToolsApp> createState() => _FileToolsAppState();
}

class _FileToolsAppState extends State<FileToolsApp> {
  bool arabic = true;
  bool darkMode = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      arabic = prefs.getBool('arabic') ?? true;
      darkMode = prefs.getBool('darkMode') ?? false;
    });
  }

  Future<void> _setArabic(bool value) async {
    setState(() => arabic = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('arabic', value);
  }

  Future<void> _setDarkMode(bool value) async {
    setState(() => darkMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', value);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'تجربة',
        themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF087F8C),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF5F8FA),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF5F8FA)),
          cardTheme: CardThemeData(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFFE5ECEF)),
            ),
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF39B8B0),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF101719),
          cardTheme: CardThemeData(
            elevation: 0,
            color: const Color(0xFF1B2528),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF344246)),
            ),
          ),
        ),
        locale: Locale(arabic ? 'ar' : 'en'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: HomePage(
          arabic: arabic,
          darkMode: darkMode,
          onLanguageChanged: _setArabic,
          onThemeChanged: _setDarkMode,
        ),
      );
}

class HomePage extends StatefulWidget {
  final bool arabic;
  final bool darkMode;
  final ValueChanged<bool> onLanguageChanged;
  final ValueChanged<bool> onThemeChanged;
  const HomePage({super.key, required this.arabic, required this.darkMode, required this.onLanguageChanged, required this.onThemeChanged});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool busy = false;
  String status = '';
  String? selectedOutputFolder;

  @override
  void initState() {
    super.initState();
    _loadOutputFolder();
  }

  Future<void> _loadOutputFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('outputFolder');
    if (saved != null && saved.isNotEmpty && mounted) {
      setState(() => selectedOutputFolder = saved);
    }
  }

  Future<void> _chooseOutputFolder() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: t('اختر مجلد حفظ الملفات الناتجة', 'Choose a folder for saved files'),
      );
      if (path == null || path.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('outputFolder', path);
      if (mounted) {
        setState(() => selectedOutputFolder = path);
        _message(t('تم اختيار مجلد الحفظ.', 'Output folder selected.'));
      }
    } catch (_) {
      _message(t('تعذر اختيار المجلد. جرّب مجلدًا آخر.', 'Could not select that folder. Please try another.'));
    }
  }
  final List<_Tool> tools = const [
    _Tool('images_pdf', Icons.picture_as_pdf_rounded, Color(0xFFE45454)),
    _Tool('image_convert', Icons.transform_rounded, Color(0xFF4776E6)),
    _Tool('image_compress', Icons.compress_rounded, Color(0xFF8B5CF6)),
    _Tool('zip', Icons.folder_zip_rounded, Color(0xFFE0A126)),
    _Tool('unzip', Icons.unarchive_rounded, Color(0xFF159A83)),
  ];

  String t(String ar, String en) => widget.arabic ? ar : en;

  Future<Directory> _outputDir() async {
    final chosen = selectedOutputFolder;
    if (chosen != null && chosen.isNotEmpty) {
      final out = Directory(chosen);
      try {
        if (await out.exists()) {
          // Test write access before relying on the selected folder.
          final probe = File('${out.path}/.filetools_write_test');
          await probe.writeAsString('ok', flush: true);
          await probe.delete();
          return out;
        }
      } catch (_) {
        if (mounted) _message(t('تعذر الحفظ في المجلد المختار؛ سيُحفظ الملف داخل مجلد التطبيق.', 'Cannot write to the selected folder; saving in the app folder instead.'));
      }
    }
    final d = await getApplicationDocumentsDirectory();
    final out = Directory('${d.path}/FileTools');
    if (!await out.exists()) await out.create(recursive: true);
    return out;
  }

  Future<List<PlatformFile>?> _pickImages({bool multiple = true}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: multiple,
      withData: true,
    );
    if (result == null) return null;
    if (result.files.length > 20) {
      _message(t('الحد الأقصى 20 صورة في العملية الواحدة.', 'Maximum 20 images per operation.'));
      return null;
    }
    if (result.files.any((f) => f.bytes == null && f.path == null)) {
      _message(t('تعذر قراءة أحد الملفات. اختر الملفات مرة أخرى.', 'Could not read one of the files. Please select them again.'));
      return null;
    }
    return result.files;
  }

  Future<Uint8List?> _bytes(PlatformFile f) async {
    if (f.bytes != null) return f.bytes!;
    if (f.path != null) return await File(f.path!).readAsBytes();
    return null;
  }

  Future<void> _run(String key) async {
    if (busy) return;
    setState(() { busy = true; status = t('جارٍ تجهيز العملية...', 'Preparing operation...'); });
    try {
      switch (key) {
        case 'images_pdf':
          await _imagesToPdf();
          break;
        case 'image_convert':
          await _convertImages();
          break;
        case 'image_compress':
          await _compressImages();
          break;
        case 'zip':
          await _makeZip();
          break;
        case 'unzip':
          await _unzip();
          break;
      }
    } catch (e) {
      _message(t('حدث خطأ أثناء معالجة الملف. تأكد من سلامة الملف وحاول مجددًا.', 'An error occurred while processing the file. Check it and try again.'));
    } finally {
      if (mounted) setState(() { busy = false; status = ''; });
    }
  }

  Future<void> _imagesToPdf() async {
    final files = await _pickImages();
    if (files == null || files.isEmpty) return;
    final doc = pw.Document();
    int done = 0;
    for (final f in files) {
      final b = await _bytes(f);
      if (b == null) continue;
      final decoded = img.decodeImage(b);
      if (decoded == null) continue;
      final normalized = img.encodeJpg(decoded, quality: 92);
      final image = pw.MemoryImage(normalized);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (_) => pw.Center(
          child: pw.Image(image, fit: pw.BoxFit.contain),
        ),
      ));
      done++;
      if (mounted) setState(() => status = '${t('معالجة الصورة', 'Processing image')} $done/${files.length}');
    }
    if (done == 0) {
      _message(t('لم نتمكن من قراءة الصور المحددة.', 'Could not read the selected images.'));
      return;
    }
    final out = await _outputDir();
    final name = 'images_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${out.path}/$name');
    await file.writeAsBytes(await doc.save(), flush: true);
    _success(name, file.path, t('تم إنشاء PDF من $done صورة.', 'Created a PDF from $done image(s).'));
  }

  Future<void> _convertImages() async {
    final files = await _pickImages();
    if (files == null || files.isEmpty) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(t('اختر الصيغة الجديدة', 'Choose output format'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          for (final ext in ['jpg', 'png'])
            ListTile(title: Text(ext.toUpperCase()), leading: const Icon(Icons.image_outlined), onTap: () => Navigator.pop(ctx, ext)),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null) return;
    final out = await _outputDir();
    int done = 0;
    for (final f in files) {
      final b = await _bytes(f);
      if (b == null) continue;
      final decoded = img.decodeImage(b);
      if (decoded == null) continue;
      List<int> encoded;
      if (choice == 'jpg') {
        encoded = img.encodeJpg(decoded, quality: 92);
      } else if (choice == 'png') {
        encoded = img.encodePng(decoded);
      } else {
        encoded = img.encodePng(decoded);
      }
      final safeBase = _baseName(f.name);
      await File('${out.path}/${safeBase}_converted.$choice').writeAsBytes(encoded, flush: true);
      done++;
      if (mounted) setState(() => status = '${t('تحويل', 'Converting')} $done/${files.length}');
    }
    _message(t('اكتمل تحويل $done ملف. مكان الحفظ داخل مجلد التطبيق: Documents/FileTools.', 'Converted $done file(s). Saved in the app folder: Documents/FileTools.'));
  }

  Future<void> _compressImages() async {
    final files = await _pickImages();
    if (files == null || files.isEmpty) return;
    final quality = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('جودة الضغط', 'Compression quality')),
        content: Text(t('جودة 80 مناسبة غالبًا لتقليل الحجم مع الحفاظ على شكل جيد.', 'Quality 80 usually reduces file size while keeping good visual quality.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 65), child: const Text('65%')),
          TextButton(onPressed: () => Navigator.pop(ctx, 80), child: const Text('80%')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 92), child: const Text('92%')),
        ],
      ),
    );
    if (quality == null) return;
    final out = await _outputDir();
    int done = 0;
    for (final f in files) {
      final b = await _bytes(f);
      if (b == null) continue;
      final decoded = img.decodeImage(b);
      if (decoded == null) continue;
      final encoded = img.encodeJpg(decoded, quality: quality);
      final safeBase = _baseName(f.name);
      await File('${out.path}/${safeBase}_compressed.jpg').writeAsBytes(encoded, flush: true);
      done++;
      if (mounted) setState(() => status = '${t('ضغط', 'Compressing')} $done/${files.length}');
    }
    _message(t('تم ضغط $done صورة بصيغة JPG. الصور الأصلية لم تتغير.', 'Compressed $done image(s) as JPG. Original images were not changed.'));
  }

  Future<void> _makeZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any, allowMultiple: true, withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    if (result.files.length > 20) {
      _message(t('الحد الأقصى 20 ملفًا في العملية الواحدة.', 'Maximum 20 files per operation.'));
      return;
    }
    final encoder = ZipFileEncoder();
    final out = await _outputDir();
    final path = '${out.path}/archive_${DateTime.now().millisecondsSinceEpoch}.zip';
    encoder.create(path);
    int added = 0;
    for (final f in result.files) {
      if (f.path == null) continue;
      encoder.addFile(File(f.path!), _baseName(f.name));
      added++;
    }
    encoder.close();
    if (added == 0) {
      _message(t('تعذر الوصول إلى الملفات المحددة.', 'Could not access the selected files.'));
      return;
    }
    _success(path.split('/').last, path, t('تم ضغط $added ملف داخل ZIP.', 'Added $added file(s) to a ZIP archive.'));
  }

  Future<void> _unzip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['zip'], withData: false,
    );
    if (result == null || result.files.isEmpty || result.files.first.path == null) return;
    final out = await _outputDir();
    final folder = Directory('${out.path}/unzipped_${DateTime.now().millisecondsSinceEpoch}');
    await folder.create(recursive: true);
    final archive = ZipDecoder().decodeBytes(await File(result.files.first.path!).readAsBytes());
    int count = 0;
    for (final item in archive) {
      // Prevent ZIP path traversal: only write files under the selected output folder.
      final normalized = item.name.replaceAll('\\', '/');
      if (normalized.startsWith('/') || normalized.split('/').contains('..')) continue;
      final target = File('${folder.path}/$normalized');
      if (item.isFile) {
        await target.parent.create(recursive: true);
        await target.writeAsBytes(item.content as List<int>, flush: true);
        count++;
      } else {
        await Directory(target.path).create(recursive: true);
      }
    }
    _success(folder.path.split('/').last, folder.path, t('تم فك الضغط عن $count ملف.', 'Extracted $count file(s).'));
  }

  String _baseName(String name) {
    final just = name.split('/').last.split('\\').last;
    final i = just.lastIndexOf('.');
    return (i > 0 ? just.substring(0, i) : just).replaceAll(RegExp(r'[^A-Za-z0-9_\-\u0600-\u06FF]'), '_');
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  Future<void> _success(String name, String path, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF159A83), size: 42),
        title: Text(t('اكتملت العملية', 'Operation complete')),
        content: SelectableText('$message\n\n$name\n$path'),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t('تمام', 'Done')))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.arabic;
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تجربة', style: TextStyle(fontWeight: FontWeight.w800)),
          centerTitle: false,
          actions: [
            IconButton(
              tooltip: widget.darkMode ? t('الوضع الفاتح', 'Light mode') : t('الوضع المظلم', 'Dark mode'),
              onPressed: () => widget.onThemeChanged(!widget.darkMode),
              icon: Icon(widget.darkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: OutlinedButton(
                onPressed: () => widget.onLanguageChanged(!widget.arabic),
                child: Text(isAr ? 'English' : 'العربية'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(colors: [Color(0xFF087F8C), Color(0xFF1C9C91)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.folder_copy_rounded, color: Colors.white, size: 34),
                  const SizedBox(height: 12),
                  Text(t('كل أدوات ملفاتك في مكان واحد', 'All your file tools in one place'), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(t('اختر أداة، ثم اختر الملفات. لا نرفع ملفاتك إلى خادم.', 'Choose a tool, then select files. Your files are not uploaded to a server.'), style: const TextStyle(color: Colors.white, height: 1.4)),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _pill(t('حد 20 صورة', '20-image limit')),
                    _pill(t('معالجة محلية', 'On-device processing')),
                    _pill(t('عربي / English', 'Arabic / English')),
                  ]),
                ]),
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.folder_open_rounded, color: Color(0xFF087F8C)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t('مجلد حفظ الملفات', 'Output folder'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                      FilledButton.tonalIcon(
                        onPressed: busy ? null : _chooseOutputFolder,
                        icon: const Icon(Icons.drive_file_move_outline),
                        label: Text(t('اختيار', 'Choose')),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      selectedOutputFolder ?? t('لم تختر مجلدًا؛ سيتم الحفظ تلقائيًا داخل مجلد التطبيق.', 'No folder selected; files will be saved automatically in the app folder.'),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                    if (selectedOutputFolder != null)
                      Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(
                        onPressed: busy ? null : () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('outputFolder');
                          if (mounted) setState(() => selectedOutputFolder = null);
                        },
                        child: Text(t('استخدام مجلد التطبيق بدلًا منه', 'Use app folder instead')),
                      )),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Text(t('اختر أداة', 'Choose a tool'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              for (final tool in tools) _toolCard(tool),
              if (busy) ...[
                const SizedBox(height: 12),
                Card(child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(status, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(),
                  ]),
                )),
              ],
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF3A3322) : const Color(0xFFFFF4DE), borderRadius: BorderRadius.circular(16)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline_rounded, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFFD782) : const Color(0xFF996515)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(t(
                    'ملاحظة: ملفات PDF والصور المضغوطة وبقية النتائج تُحفظ تلقائيًا في المجلد الذي تختاره. إذا تعذرت الكتابة إليه، يستخدم التطبيق مجلده الخاص. الملفات الأصلية لا تتغير.',
                    'PDFs, compressed images, and other results are saved automatically to your chosen folder. If it is not writable, the app uses its own folder. Originals are unchanged.',
                  ), style: TextStyle(height: 1.45, color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFFE7B0) : const Color(0xFF654A16)))),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(30)),
    child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
  );

  Widget _toolCard(_Tool tool) {
    String title;
    String desc;
    switch (tool.key) {
      case 'images_pdf':
        title = widget.arabic ? 'الصور إلى PDF' : 'Images to PDF';
        desc = widget.arabic ? 'اجمع حتى 20 صورة في ملف PDF واحد مرتب.' : 'Combine up to 20 images into one ordered PDF.';
        break;
      case 'image_convert':
        title = widget.arabic ? 'تحويل صيغة الصور' : 'Convert image format';
        desc = widget.arabic ? 'حوّل الصور إلى JPG أو PNG.' : 'Convert images to JPG or PNG.';
        break;
      case 'image_compress':
        title = widget.arabic ? 'ضغط الصور' : 'Compress images';
        desc = widget.arabic ? 'اختر جودة الضغط واحتفظ بالأصل كما هو.' : 'Choose compression quality and keep the original unchanged.';
        break;
      case 'zip':
        title = widget.arabic ? 'إنشاء ملف ZIP' : 'Create ZIP archive';
        desc = widget.arabic ? 'اجمع حتى 20 ملفًا في أرشيف مضغوط.' : 'Bundle up to 20 files into a ZIP archive.';
        break;
      default:
        title = widget.arabic ? 'فك ضغط ZIP' : 'Extract ZIP';
        desc = widget.arabic ? 'استخرج الملفات إلى مجلد داخل التطبيق بأمان.' : 'Extract files safely into an app folder.';
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: busy ? null : () => _run(tool.key),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: tool.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(16)),
              child: Icon(tool.icon, color: tool.color, size: 27),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              Text(desc, style: const TextStyle(color: Color(0xFF65737A), height: 1.35, fontSize: 13)),
            ])),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF829097)),
          ]),
        ),
      ),
    );
  }
}

class _Tool {
  final String key;
  final IconData icon;
  final Color color;
  const _Tool(this.key, this.icon, this.color);
}
