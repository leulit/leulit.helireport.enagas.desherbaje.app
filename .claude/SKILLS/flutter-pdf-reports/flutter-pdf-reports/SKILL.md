---
name: flutter-pdf-reports
description: >
  Flutter PDF generation and reading skill — use this whenever the project
  involves generating PDF reports, filling PDF templates, reading PDF content,
  creating inspection reports, invoices, certificates, or any document output.
  Triggers on mentions of PDF, report, invoice, certificate, document generation,
  pdf package, printing, template, or any file output that users need to
  download or share. Always apply alongside flutter-core.
---

# Flutter PDF Reports Skill

> Always apply **flutter-core** in parallel. This skill extends it for PDF work.

## Core Stack

| Package | Purpose |
|---|---|
| `pdf: ^3.11.1` | Pure Dart PDF generation — layout engine, fonts, images |
| `printing: ^5.13.1` | Preview, print, share, and save PDFs cross-platform |
| `syncfusion_flutter_pdf` | Read/fill existing PDF forms (commercial, free community license) |
| `path_provider: ^2.1.3` | Save files on iOS/Android |
| `share_plus: ^10.0.0` | Share PDF via OS share sheet |

---

## Architecture

PDF work always happens in an isolate — never block the UI thread.

```
Controller.generateReport(data)
    │
    ├── compute(_buildPdfIsolate, data)  ← isolate
    │       │
    │       └── PdfBuilder.build(data) → Uint8List
    │
    └── PdfService.saveOrShare(bytes)
```

---

## PDF Generation with `pdf` Package

### Page Layout & Structure

```dart
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class InspectionReportBuilder {
  static Future<Uint8List> build(InspectionReportData data) async {
    final doc = pw.Document(
      theme: await _buildTheme(),
      title: data.title,
      author: data.inspectorName,
      creator: 'MyApp v1.0',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => _buildHeader(context, data),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _buildTitleSection(data),
          pw.SizedBox(height: 16),
          _buildInfoTable(data),
          pw.SizedBox(height: 16),
          _buildFindings(data.findings),
          if (data.images.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            _buildImageGrid(data.images),
          ],
          _buildSignatureSection(data),
        ],
      ),
    );

    return doc.save();
  }

  static Future<pw.ThemeData> _buildTheme() async {
    // Embed custom fonts — required for non-Latin scripts
    final regular = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    return pw.ThemeData.withFont(base: regular, bold: bold);
  }

  static pw.Widget _buildHeader(pw.Context context, InspectionReportData data) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
      ),
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(data.companyName,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.Text('Report #${data.reportNumber}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Generated: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
        pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ],
    );
  }

  static pw.Widget _buildInfoTable(InspectionReportData data) {
    return pw.TableHelper.fromTextArray(
      headers: const ['Field', 'Value'],
      data: [
        ['Inspector', data.inspectorName],
        ['Date', DateFormat('dd/MM/yyyy').format(data.date)],
        ['Location', data.location],
        ['Pipeline ID', data.pipelineId],
        ['Status', data.status.displayName],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
      cellAlignment: pw.Alignment.centerLeft,
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(2),
      },
    );
  }

  static pw.Widget _buildFindings(List<Finding> findings) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Findings', style: pw.TextStyle(
          fontSize: 14, fontWeight: pw.FontWeight.bold,
        )),
        pw.SizedBox(height: 8),
        ...findings.map((f) => _buildFindingItem(f)),
      ],
    );
  }

  static pw.Widget _buildFindingItem(Finding finding) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(children: [
            pw.Container(
              width: 8, height: 8,
              decoration: pw.BoxDecoration(
                color: _severityColor(finding.severity),
                shape: pw.BoxShape.circle,
              ),
            ),
            pw.SizedBox(width: 6),
            pw.Text(finding.title,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ]),
          pw.SizedBox(height: 4),
          pw.Text(finding.description,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
        ],
      ),
    );
  }

  static pw.Widget _buildImageGrid(List<Uint8List> images) {
    const cols = 2;
    final rows = (images.length / cols).ceil();
    return pw.Column(
      children: List.generate(rows, (row) => pw.Row(
        children: List.generate(cols, (col) {
          final idx = row * cols + col;
          if (idx >= images.length) return pw.Expanded(child: pw.SizedBox());
          return pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Image(pw.MemoryImage(images[idx]),
                  height: 150, fit: pw.BoxFit.cover),
            ),
          );
        }),
      )),
    );
  }

  static pw.Widget _buildSignatureSection(InspectionReportData data) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
      children: [
        _signatureBox('Inspector', data.inspectorName, data.inspectorSignature),
        _signatureBox('Supervisor', data.supervisorName, data.supervisorSignature),
      ],
    );
  }

  static pw.Widget _signatureBox(
      String role, String name, Uint8List? signature) {
    return pw.Column(children: [
      pw.Container(
        width: 180, height: 60,
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide()),
        ),
        child: signature != null
            ? pw.Image(pw.MemoryImage(signature), fit: pw.BoxFit.contain)
            : pw.SizedBox(),
      ),
      pw.SizedBox(height: 4),
      pw.Text(name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      pw.Text(role, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
    ]);
  }

  static PdfColor _severityColor(Severity s) => switch (s) {
    Severity.critical => PdfColors.red,
    Severity.high => PdfColors.orange,
    Severity.medium => PdfColors.yellow,
    Severity.low => PdfColors.green,
  };
}
```

---

## Controller Integration (GetX)

```dart
class ReportController extends GetxController {
  final isGenerating = false.obs;
  final generatedBytes = Rxn<Uint8List>();

  Future<void> generateReport(InspectionReportData data) async {
    isGenerating.value = true;
    try {
      // Always in isolate — PDF generation is CPU-heavy
      final bytes = await compute(InspectionReportBuilder.build, data);
      generatedBytes.value = bytes;
    } catch (e) {
      Get.snackbar('Error', 'Failed to generate report: $e');
    } finally {
      isGenerating.value = false;
    }
  }

  Future<void> previewReport() async {
    final bytes = generatedBytes.value;
    if (bytes == null) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> saveReport(String fileName) async {
    final bytes = generatedBytes.value;
    if (bytes == null) return;
    if (kIsWeb) {
      // Web: trigger browser download
      await Printing.sharePdf(bytes: bytes, filename: '$fileName.pdf');
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName.pdf');
      await file.writeAsBytes(bytes);
      Get.snackbar('Saved', 'Report saved to ${file.path}');
    }
  }

  Future<void> shareReport(String fileName) async {
    final bytes = generatedBytes.value;
    if (bytes == null) return;
    await Printing.sharePdf(bytes: bytes, filename: '$fileName.pdf');
  }
}
```

---

## Reading / Filling Existing PDFs (Syncfusion)

```dart
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfFormFiller {
  /// Fill form fields in an existing PDF template.
  static Future<Uint8List> fillTemplate({
    required Uint8List templateBytes,
    required Map<String, String> fieldValues,
    bool flattenAfterFill = true, // flatten = make fields read-only
  }) async {
    final document = PdfDocument(inputBytes: templateBytes);
    final form = document.form;

    for (final entry in fieldValues.entries) {
      final field = form.fields.getByName(entry.key);
      if (field == null) continue;
      if (field is PdfTextBoxField) field.text = entry.value;
      if (field is PdfCheckBoxField) field.isChecked = entry.value == 'true';
      if (field is PdfComboBoxField) field.selectedValue = entry.value;
    }

    if (flattenAfterFill) form.flatten();

    final bytes = await document.save();
    document.dispose();
    return Uint8List.fromList(bytes);
  }

  /// Extract all text from a PDF for search/indexing.
  static Future<String> extractText(Uint8List pdfBytes) async {
    return compute(_extractTextIsolate, pdfBytes);
  }
}

// Top-level — runs in isolate
String _extractTextIsolate(Uint8List bytes) {
  final document = PdfDocument(inputBytes: bytes);
  final extractor = PdfTextExtractor(document);
  final text = extractor.extractText();
  document.dispose();
  return text;
}
```

---

## PDF Preview Widget

```dart
class PdfPreviewPage extends GetView<ReportController> {
  const PdfPreviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Preview'),
        actions: [
          Obx(() => controller.isGenerating.value
            ? const CircularProgressIndicator()
            : Row(children: [
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: () => controller.shareReport('inspection_report'),
                ),
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: () => controller.saveReport('inspection_report'),
                ),
              ])),
        ],
      ),
      body: Obx(() {
        final bytes = controller.generatedBytes.value;
        if (bytes == null) return const Center(child: CircularProgressIndicator());
        return PdfPreview(
          build: (_) async => bytes,
          allowPrinting: true,
          allowSharing: true,
          canChangePageFormat: false,
        );
      }),
    );
  }
}
```

---

## Performance Rules for PDF

1. **Always use `compute()`** for generation — even simple PDFs can take 200ms+.
2. **Compress images before embedding** — use `image` package to resize to 800px max before adding to PDF.
3. **Embed fonts once** — load font assets once in the theme, not per widget.
4. **Dispose Syncfusion documents** — always call `document.dispose()` after save.
5. **Web PDF download** — use `Printing.sharePdf()` which handles browser download; `dart:io` not available on web.

```dart
// Compress image before embedding in PDF
Future<Uint8List> compressForPdf(Uint8List original, {int maxSize = 800}) async {
  return compute(_compressIsolate, (original, maxSize));
}

({Uint8List bytes, int maxSize}) _compressInput(Uint8List b, int s) => (bytes: b, maxSize: s);

Uint8List _compressIsolate((Uint8List, int) args) {
  final (bytes, maxSize) = args;
  var image = img.decodeImage(bytes)!;
  if (image.width > maxSize || image.height > maxSize) {
    image = img.copyResize(image,
        width: image.width > image.height ? maxSize : null,
        height: image.height >= image.width ? maxSize : null);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}
```
