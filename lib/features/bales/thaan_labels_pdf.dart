import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Build + open the print dialog for one bale's QR-coded Thaans, laid out
/// for an 80mm thermal receipt roll — the same format slk-core's own
/// `/thaans/print/[baleId]` renders, so a printout from either place looks
/// the same. `pw.Page`, not `pw.MultiPage`: `PdfPageFormat.roll80`'s height
/// is unbounded (a roll has no fixed length), and `MultiPage` asserts that
/// page height must be finite since its whole job is paginating across
/// fixed-size pages — `Page` has no such pagination step, so it's the one
/// that actually supports growing to fit however many labels there are.
Future<void> printThaanLabels({
  required String baleCode,
  required List<String> codes,
}) async {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80,
      margin: pw.EdgeInsets.zero,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < codes.length; i++)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 10),
              decoration: i == 0
                  ? null
                  : const pw.BoxDecoration(
                      border: pw.Border(top: pw.BorderSide(width: 0.5, style: pw.BorderStyle.dashed)),
                    ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(baleCode, style: const pw.TextStyle(fontSize: 8)),
                  pw.SizedBox(height: 4),
                  pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: codes[i], width: 120, height: 120),
                  pw.SizedBox(height: 4),
                  pw.Text(codes[i], style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
    ),
  );
  await Printing.layoutPdf(onLayout: (_) => doc.save());
}
