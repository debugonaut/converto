import 'package:flutter/material.dart';
import '../models/gui/tool_definition.dart';

IconData toolIcon(ToolId id) => switch (id) {
  ToolId.convert => Icons.swap_horiz_rounded,
  ToolId.merge => Icons.call_merge_rounded,
  ToolId.split => Icons.call_split_rounded,
  ToolId.compress => Icons.compress_rounded,
  ToolId.organize => Icons.dashboard_outlined,
  ToolId.editImage => Icons.tune_rounded,
  ToolId.watermark => Icons.branding_watermark_outlined,
  ToolId.protect => Icons.lock_outline_rounded,
  ToolId.redact => Icons.format_color_fill_outlined,
  ToolId.pdfImages => Icons.image_outlined,
  ToolId.pdfText => Icons.notes_rounded,
  ToolId.pdfOffice => Icons.description_outlined,
  ToolId.extract => Icons.content_copy_outlined,
  ToolId.rotate => Icons.rotate_90_degrees_cw_outlined,
  ToolId.pageNumbers => Icons.format_list_numbered_rounded,
  ToolId.crop => Icons.crop_rounded,
  ToolId.pdfa => Icons.inventory_2_outlined,
  ToolId.unlock => Icons.lock_open_rounded,
  ToolId.info => Icons.info_outline_rounded,
};
