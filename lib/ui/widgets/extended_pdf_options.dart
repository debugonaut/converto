import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../core/theme/app_theme.dart';
import '../../models/gui/tool_definition.dart';

typedef PdfOptionField =
    Widget Function(
      String name,
      String label, {
      String initial,
      String? hint,
      bool secret,
      String? help,
    });
typedef PdfOptionChoice =
    Widget Function(
      String name,
      String label,
      Map<String, String> choices,
      String fallback,
    );

/// Focused options for extended PDF workflows; execution stays in services.
class ExtendedPdfOptions extends StatelessWidget {
  final ToolId tool;
  final Map<String, Object> options;
  final PdfOptionField field;
  final PdfOptionChoice choice;
  final void Function(String, bool) onToggle;
  final Future<void> Function(String, List<String>) onPick;
  final bool locked;
  const ExtendedPdfOptions({
    super.key,
    required this.tool,
    required this.options,
    required this.field,
    required this.choice,
    required this.onToggle,
    required this.onPick,
    this.locked = false,
  });
  String value(String name, [String fallback = '']) =>
      '${options[name] ?? fallback}';
  Widget note(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      text,
      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
    ),
  );
  Widget toggle(String name, String label) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(label, style: const TextStyle(fontSize: 14)),
    value: options[name] != false,
    onChanged: locked ? null : (v) => onToggle(name, v),
  );
  Widget picker(String name, String label, List<String> extensions) {
    final path = value(name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (path.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                p.basename(path),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          OutlinedButton.icon(
            onPressed: locked ? null : () => onPick(name, extensions),
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: Text('${path.isEmpty ? 'Choose' : 'Change'} $label'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (tool == ToolId.compare) ...[
        note(
          'Choose exactly two PDFs. The first file is the left version; the second is the right version. A standalone HTML report includes changed pages and can be exported.',
        ),
        field('leftPassword', 'Left PDF password (if encrypted)', secret: true),
        field(
          'rightPassword',
          'Right PDF password (if encrypted)',
          secret: true,
        ),
        note(
          'Comparison checks text and sampled page pixels. It is not a semantic or legal review.',
        ),
      ],
      if (tool == ToolId.repair) ...[
        field('password', 'PDF password (if encrypted)', secret: true),
        note(
          'Rebuilds recoverable PDF structure into a new file. Missing content cannot be restored. Rewriting can invalidate existing digital signatures.',
        ),
      ],
      if (tool == ToolId.clean) ...[
        toggle('cleanMetadata', 'Remove document metadata'),
        toggle('cleanJavascript', 'Remove JavaScript'),
        toggle('cleanAttachments', 'Remove embedded files'),
        field('password', 'PDF password (if encrypted)', secret: true),
        note(
          'Only the selected content is removed from the new copy. Review the result before sharing.',
        ),
      ],
      if (tool == ToolId.flatten) ...[
        toggle('flattenForms', 'Flatten form fields'),
        toggle('flattenAnnotations', 'Flatten annotations'),
        field('password', 'PDF password (if encrypted)', secret: true),
        note(
          'Bakes selected interactive content into the pages. Flattening does not encrypt or lock the PDF. Unsupported form appearances are reported instead of silently removed.',
        ),
      ],
      if (tool == ToolId.sign) ...[
        picker('certificatePath', 'certificate', const ['p12', 'pfx']),
        field('certificatePassword', 'Certificate password', secret: true),
        field('reason', 'Reason (optional)'),
        field('location', 'Location (optional)'),
        note(
          'Uses your local certificate for this run. The credential selection and password are cleared afterward. Certificate trust depends on its issuing chain; self-signing does not establish a verified identity.',
        ),
      ],
      if (tool == ToolId.ocr) ...[
        choice('format', 'OCR output', const {
          'txt': 'Text file',
          'pdf': 'Searchable PDF',
        }, 'txt'),
        field(
          'language',
          'Installed languages',
          initial: 'eng',
          hint: 'eng or eng+hin',
        ),
        choice('dpi', 'OCR resolution', const {
          '150': '150 DPI',
          '300': '300 DPI',
          '600': '600 DPI',
        }, '300'),
        field('password', 'PDF password (if encrypted)', secret: true),
        note(
          'Uses a locally installed desktop Tesseract engine and language data. No engine or model is downloaded by Converto.',
        ),
      ],
      if (tool == ToolId.split) ...[
        choice('splitMode', 'Split mode', const {
          'count': 'Pages per part',
          'ranges': 'Page ranges',
          'size': 'Target file size',
        }, 'count'),
        if (value('splitMode', 'count') == 'size') ...[
          field('maxSizeMb', 'Target size (MB)', initial: '10'),
          note(
            'A single page that exceeds the target is kept in its own part and reported. No page is dropped.',
          ),
        ] else if (value('splitMode', 'count') == 'ranges')
          field(
            'pages',
            'Page ranges',
            hint: '1-3, 4-6, 7',
            help: 'Each comma-separated group becomes a PDF.',
          )
        else
          field('every', 'Pages per part', initial: '1'),
      ],
      if (tool == ToolId.pdfImages) ...[
        choice('imageMode', 'Image export', const {
          'pages': 'Render PDF pages',
          'extract': 'Extract embedded images',
        }, 'pages'),
        if (value('imageMode', 'pages') == 'extract')
          note(
            'Exports embedded image objects in their original supported encoding. These may differ from the displayed page, especially with masks or transforms. Text and vector-only PDFs contain no extractable images.',
          ),
      ],
      if (tool == ToolId.watermark) ...[
        choice('watermarkKind', 'Watermark type', const {
          'text': 'Text',
          'image': 'Image or logo',
        }, 'text'),
        if (value('watermarkKind', 'text') == 'image') ...[
          picker('watermarkImage', 'watermark image', const [
            'jpg',
            'jpeg',
            'png',
          ]),
          field('imageWidthPercent', 'Image width (% of page)', initial: '25'),
        ] else ...[
          field('text', 'Watermark text', hint: 'DRAFT'),
          field('angle', 'Angle (degrees)', initial: '45'),
          field('fontSize', 'Font size (pt)', initial: '54'),
        ],
        field('opacity', 'Opacity (0–1)', initial: '0.25'),
      ],
      if ([ToolId.watermark, ToolId.pageNumbers].contains(tool)) ...[
        field('pages', 'Apply to pages (blank = all)', hint: '1-3, 5'),
        choice('position', 'Page position', const {
          'center': 'Center',
          'topLeft': 'Top left',
          'topRight': 'Top right',
          'bottomLeft': 'Bottom left',
          'bottomRight': 'Bottom right',
        }, tool == ToolId.pageNumbers ? 'bottomRight' : 'center'),
        field('margin', 'Margin (pt)', initial: '20'),
        if (tool == ToolId.pageNumbers)
          field('startNumber', 'Starting number', initial: '1'),
        if (tool == ToolId.pageNumbers)
          note(
            'Numbers are sequential across the selected pages, starting at the value above. Other pages stay unchanged.',
          ),
      ],
      if (tool == ToolId.convert && value('format') == 'html') ...[
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Preserve PDF appearance',
            style: TextStyle(fontSize: 14),
          ),
          value: options['htmlLayout'] == true,
          onChanged: locked ? null : (v) => onToggle('htmlLayout', v),
        ),
        note(
          'Appearance mode embeds page images in one HTML file. It preserves layout but does not retain selectable text.',
        ),
      ],
    ],
  );
}
