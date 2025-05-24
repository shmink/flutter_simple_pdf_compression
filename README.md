# Simple PDF Compression

A Flutter package for compressing PDFs. This package provides a simple use but with a more complex algorithm to work out optimal compression ratios.

## Features

- **PDF Compression**: Compress PDF files with different compression levels
- **Customizable**: Configure compression parameters to suit your needs

## Getting Started

Add the package to your `pubspec.yaml` file:

```bash
flutter pub add simple_pdf_compression
```
or
```yaml
dependencies:
  simple_pdf_compression: ^0.0.1
```

Then run:

```bash
flutter pub get
```

## Usage

```dart
import 'dart:io';
import 'package:simple_pdf_compression/simple_pdf_compression.dart';

void main() async {
  final inputPdf = File('/path/to/your/input.pdf');

  final compressedPdf = await compressPdf(
    inputPdf,
    thresholdSize: 500 * 1024, // Optional: 500 KB
    quality: 60,               // Optional: 0 (most compression) to 100 (lowest compression)
  );

  print('Compressed PDF saved at: ${compressedPdf.path}');
  print('Original size: ${inputPdf.lengthSync()} bytes');
  print('Compressed size: ${compressedPdf.lengthSync()} bytes');
}
```

## Additional Information

- The compressed files are saved to the temporary directory by default
- Without passing `quality` the quality of the PDF is worked out and IQR is used to work out an appropriate compression amount.
- Inspired by @rathorerahul586 package `pdf_handler`

## License

This project is licensed under the MIT License