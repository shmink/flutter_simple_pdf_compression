import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw_widgets;
import 'package:pdfx/pdfx.dart';

class PDFCompression {
  /// - If [thresholdSize] is set and the original file is smaller than or equal to this value,
  ///   the original file is returned unchanged and uncompressed.
  /// - If [quality] is not provided, an internal algorithm attempts to calculate an appropriate
  ///   quality level based on the document and size threshold.
  Future<File> compressPdf(File pdfFile,
      {int thresholdSize = 0, int? quality}) async {
    if (!pdfFile.path.endsWith('.pdf')) {
      throw ('Invalid pdf file. File path must be end with .pdf extension');
    }

    var pdfDocument = await PdfDocument.openFile(pdfFile.path);

    var originalFileSize = pdfFile.lengthSync();

    if (originalFileSize <= thresholdSize) {
      return pdfFile;
    }

    // calculate image compression ratio so that we get a balance between file size and quality
    // but it can be overridden if we want to
    quality = quality ?? await _calculatePdfQuality(pdfDocument, thresholdSize);

    List<File> compressedImages = [];
    try {
      for (int i = 1; i <= pdfDocument.pagesCount; i++) {
        final page = await pdfDocument.getPage(i);
        final pageImage = await page.render(
          width: page.width,
          height: page.height,
        );
        await page.close();

        if (pageImage != null) {
          File compressedImage = await _compressImage(pageImage.bytes, quality);

          compressedImages.add(compressedImage);
        }
      }
    } catch (e, s) {
      throw Exception(["Failed to compress PDF", s]);
    }

    // take the compressed pages/images and make them back into a PDF
    var finalDocument = await _convertToPdf(compressedImages);

    return finalDocument;
  }

  Future<File> _compressImage(Uint8List imageBytes, int quality) async {
    img.Image? image = img.decodeImage(imageBytes);

    if (image == null) {
      throw Exception('Unable to decode image');
    }

    Uint8List compressedImageBytes =
        Uint8List.fromList(img.encodeJpg(image, quality: quality));

    final tempDir = await getTemporaryDirectory();
    final compressedImageFile = File(
        '${tempDir.path}/compressed_image_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await compressedImageFile.writeAsBytes(compressedImageBytes);

    return compressedImageFile;
  }

  Future<File> _convertToPdf(List<File> imageFiles) async {
    final pdf = pw_widgets.Document();

    // Add each image as a page in the new PDF
    for (File imageFile in imageFiles) {
      final image = pw_widgets.MemoryImage(imageFile.readAsBytesSync());
      pdf.addPage(pw_widgets.Page(build: (pw_widgets.Context context) {
        return pw_widgets.Center(
          child: pw_widgets.Image(image),
        ); // Center
      }));
    }

    final tempDir = await getTemporaryDirectory();
    final outputPdfFile = File('${tempDir.path}/compressed_output.pdf');
    await outputPdfFile.writeAsBytes(await pdf.save());

    return outputPdfFile;
  }

  List<int> _adjustOutliersIQR(List<int> values) {
    if (values.isEmpty) return values;

    values.sort();

    // calculate quarter medians
    int q1Index = (values.length * 0.25).floor();
    int q3Index = (values.length * 0.75).floor();
    int q1 = values[q1Index];
    int q3 = values[q3Index];
    int iqr = q3 - q1;

    // define bounds for outliers
    // the 1.5 multiplier in IQR calculations is a standard statistical convention
    int lowerBound = q1 - (1.5 * iqr).round();
    int upperBound = q3 + (1.5 * iqr).round();

    // swap super large value for upper bound and super small value for lower bound
    List<int> adjustedValues = values.map((size) {
      if (size < lowerBound) return lowerBound;
      if (size > upperBound) return upperBound;
      return size;
    }).toList();

    return adjustedValues;
  }

  Future<int> _calculatePdfQuality(
      PdfDocument pdfDocument, int thresholdSize) async {
    var allowedSizePerImage = thresholdSize / pdfDocument.pagesCount;
    List<int> pageSizes = [];

    try {
      // Collect page sizes - in a try block just incase there's a corrupted PDF or some other nonsense
      for (int i = 1; i <= pdfDocument.pagesCount; i++) {
        final page = await pdfDocument.getPage(i);
        final pageImage = await page.render(
          width: page.width,
          height: page.height,
        );
        await page.close();
        if (pageImage?.bytes != null) {
          pageSizes.add(pageImage!.bytes.lengthInBytes);
        }
      }
    } catch (e, s) {
      throw Exception(["Failed to calculate PDF quality", s]);
    }

    // A whole lot of (fun?) maths basically incase we get like a 10 page document
    // with one page that's 20mb and the rest are 1mb creating a dumb compression ratio
    // that would compress the pages to illegible sizes
    var adjustedSizes = _adjustOutliersIQR(pageSizes);

    // Calculate average from adjusted sizes
    int sum = adjustedSizes.reduce((a, b) => a + b);
    var averagePageSize = sum ~/ adjustedSizes.length;

    double compressionRatio = allowedSizePerImage / averagePageSize;

    // Clamp the compression ratio to a minimum of 35% and maximum of 100% incase math goes mad
    // 35 was chosen as the minimum because anything lower and the compression is too severe
    // making text illegible
    return (compressionRatio * 100).clamp(35, 100).toInt();
  }
}
