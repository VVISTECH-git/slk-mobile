import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// A printable sheet of QR labels — one per piece tag — to attach to the cut
/// pieces. Laid out 3-up on A4. Uses the `pdf` package's built-in QR barcode
/// (no extra dependency).
Future<Uint8List> buildLabelSheetPdf(List<String> tags, {String? batchCode}) async {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        pw.Header(level: 0, text: 'Piece labels${batchCode != null ? ' · $batchCode' : ''} (${tags.length})'),
        pw.Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final t in tags)
              pw.Container(
                width: 160,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                child: pw.Column(
                  children: [
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: t,
                      width: 90,
                      height: 90,
                      drawText: false,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(t, style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}

/// A delivery / job-work challan PDF: header with challan no, vendor, stage,
/// and the full list of dispatched piece tags for the vendor to sign against.
Future<Uint8List> buildChallanPdf(Map<String, dynamic> order) async {
  final doc = pw.Document();
  final pieces = (order['pieces'] as List? ?? []);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Job Work Challan', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text('${order['challanNo']}'),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('Vendor: ${order['vendorName'] ?? '—'}'),
              pw.Text('Stage: ${order['stageName'] ?? '—'}'),
              pw.Text('Pieces: ${pieces.length}'),
            ]),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['#', 'Tag code', 'Size', 'Status'],
          cellStyle: const pw.TextStyle(fontSize: 10),
          headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          data: [
            for (var i = 0; i < pieces.length; i++)
              [
                '${i + 1}',
                '${(pieces[i] as Map)['tag']}',
                '${pieces[i]['size'] ?? ''}',
                '${pieces[i]['status']}',
              ],
          ],
        ),
        pw.SizedBox(height: 40),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Dispatched by: ${order['dispatchedBy'] ?? ''}'),
            pw.Text('Vendor signature: __________________'),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}
