import '../../models/gui/tool_definition.dart';
import '../../models/gui/file_preview.dart';
import '../../models/scan_options.dart';
import '../../models/pdf_layout_options.dart';
import '../pdf/pdf_engine.dart';

class WorkspaceValidation {
  static Map<String, String> check(
    ToolId tool,
    Map<String, Object> options, {
    FilePreview? preview,
  }) {
    final errors = <String, String>{};
    if (tool == ToolId.scanPdf) {
      try {
        ScanOptions.fromMap(options);
      } on ArgumentError catch (error) {
        errors['scan'] = '${error.message}';
      }
    }
    String text(String name) => '${options[name] ?? ''}'.trim();
    int? integer(
      String name, {
      int minimum = 1,
      int? maximum,
      bool optional = false,
    }) {
      if (optional && text(name).isEmpty) return null;
      final value = int.tryParse(text(name));
      if (value == null ||
          value < minimum ||
          (maximum != null && value > maximum))
        errors[name] =
            'Enter ${minimum == 0 ? 'a non-negative' : 'a positive'} whole number${maximum == null ? '' : ' up to $maximum'}.';
      return value;
    }

    double? decimal(String name, {double? minimum, double? maximum}) {
      final value = double.tryParse(text(name));
      if (value == null ||
          !value.isFinite ||
          (minimum != null && value < minimum) ||
          (maximum != null && value > maximum))
        errors[name] =
            'Enter a valid number${minimum == null ? '' : ' from $minimum'}${maximum == null ? '' : ' to $maximum'}.';
      return value;
    }

    if ((tool == ToolId.redact ||
            (tool == ToolId.watermark && text('watermarkKind') != 'image')) &&
        text('text').isEmpty)
      errors['text'] = tool == ToolId.watermark
          ? 'Enter watermark text.'
          : 'Enter the text to redact.';
    if (tool == ToolId.watermark) {
      decimal('opacity', minimum: 0, maximum: 1);
      if (text('watermarkKind') == 'image') {
        if (text('watermarkImage').isEmpty)
          errors['watermarkImage'] =
              'Choose a local JPG or PNG watermark image.';
      } else {
        decimal('angle');
        decimal('fontSize', minimum: .1);
      }
    }
    if ([ToolId.watermark, ToolId.pageNumbers].contains(tool)) {
      try {
        PdfLayoutOptions.fromMap(options);
      } on ArgumentError catch (error) {
        errors['layout'] = '${error.message}';
      }
      if (text('pages').isNotEmpty && preview?.kind == 'pdf') {
        try {
          PdfEngine.parsePageList(text('pages'), preview!.pageCount);
        } on ArgumentError catch (error) {
          errors['pages'] = '${error.message}';
        } on FormatException catch (error) {
          errors['pages'] = error.message;
        }
      }
    }
    if (tool == ToolId.sign && text('certificatePath').isEmpty)
      errors['certificatePath'] = 'Choose a local P12 or PFX certificate.';
    if (tool == ToolId.flatten &&
        options['flattenForms'] == false &&
        options['flattenAnnotations'] == false)
      errors['flatten'] = 'Choose forms, annotations or both.';
    if (tool == ToolId.clean &&
        options['cleanMetadata'] == false &&
        options['cleanJavascript'] == false &&
        options['cleanAttachments'] == false)
      errors['clean'] = 'Choose at least one kind of content to remove.';
    if (tool == ToolId.ocr) {
      integer('dpi', minimum: 72, maximum: 600);
      if (!RegExp(
        r'^[a-zA-Z0-9_]+(?:\+[a-zA-Z0-9_]+)*$',
      ).hasMatch(text('language')))
        errors['language'] =
            'Enter installed language codes, for example eng or eng+hin.';
    }
    if ([ToolId.protect, ToolId.unlock].contains(tool) &&
        text('password').isEmpty)
      errors['password'] = 'Enter a password.';
    if (tool == ToolId.protect && text('password') != text('confirmPassword'))
      errors['confirmPassword'] = 'Passwords do not match.';
    if ([ToolId.extract, ToolId.organize].contains(tool) &&
        text('pages').isEmpty)
      errors['pages'] = 'Select at least one page.';
    if (([ToolId.extract, ToolId.organize].contains(tool) ||
            (tool == ToolId.split &&
                !['count', 'size'].contains(text('splitMode')))) &&
        text('pages').isNotEmpty &&
        preview?.kind == 'pdf') {
      try {
        PdfEngine.parsePageGroups(text('pages'), preview!.pageCount);
      } on ArgumentError catch (error) {
        errors['pages'] = '${error.message}';
      } on FormatException catch (error) {
        errors['pages'] = error.message;
      }
    }
    if (tool == ToolId.split) {
      if (text('splitMode') == 'size')
        decimal('maxSizeMb', minimum: .000001, maximum: 1048576);
      else if (text('pages').isEmpty)
        integer('every');
    }
    if (tool == ToolId.pdfImages && text('imageMode') != 'extract')
      integer('dpi');
    if (tool == ToolId.crop) {
      final margins = [
        'left',
        'top',
        'right',
        'bottom',
      ].map((name) => decimal(name, minimum: 0)).toList();
      if (errors.isEmpty) {
        if (margins.every((value) => value == 0))
          errors['left'] = 'Drag a crop area or set at least one margin.';
        else if (preview != null &&
            preview.width > 0 &&
            preview.height > 0 &&
            (margins[0]! + margins[2]! >= preview.width ||
                margins[1]! + margins[3]! >= preview.height)) {
          errors['left'] = 'Crop margins must leave a positive page area.';
        }
      }
    }
    if (tool == ToolId.editImage) {
      integer('width', optional: true);
      integer('height', optional: true);
      integer('quality', maximum: 100);
      final fields = ['cropX', 'cropY', 'cropWidth', 'cropHeight'];
      final present = fields.where((name) => text(name).isNotEmpty).length;
      if (present > 0 && present < 4) {
        for (final name in fields) {
          if (text(name).isEmpty)
            errors[name] = 'Fill all crop values or leave all blank.';
        }
      } else if (present == 4) {
        final x = integer('cropX', minimum: 0),
            y = integer('cropY', minimum: 0);
        final width = integer('cropWidth'), height = integer('cropHeight');
        if (errors.isEmpty && preview != null && preview.width > 0) {
          final swapped = (int.tryParse(text('degrees')) ?? 0) % 180 != 0;
          final sourceWidth = swapped ? preview.height : preview.width;
          final sourceHeight = swapped ? preview.width : preview.height;
          if (x! + width! > sourceWidth || y! + height! > sourceHeight)
            errors['cropWidth'] =
                'Crop rectangle must fit inside the rotated image.';
        }
      }
    }
    return errors;
  }
}
