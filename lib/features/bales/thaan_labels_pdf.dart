import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Build + open the print dialog for one bale's QR-coded Thaans, laid out
/// as a grid on A4 — the same page size and label-grid shape
/// `piece_labels_pdf.dart` already uses for piece tags, and the same page
/// size the tax invoice prints on. No thermal roll printer is set up for
/// this app; A4 is the one paper size actually proven to work here.
Future<void> printThaanLabels({
  required String baleCode,
  required List<String> codes,
}) async {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(16),
      build: (ctx) => [
        pw.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: codes
              .map(
                (c) => pw.Container(
                  width: 168,
                  height: 92,
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: c, width: 66, height: 66),
                      pw.SizedBox(width: 6),
                      pw.Expanded(
                        child: pw.Column(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(baleCode, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                            pw.SizedBox(height: 3),
                            pw.Text(c, style: const pw.TextStyle(fontSize: 8.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    ),
  );
  await Printing.layoutPdf(onLayout: (_) => doc.save());
}
