import 'edit_options.dart';
import 'file_item.dart';

enum JobStatus {
  queued,
  processing,
  completed,
  failed,
  cancelled,
}

class ConversionJob {
  final String id;
  final FileItem sourceFile;
  final String targetFormat;
  final JobStatus status;
  final double progress; // 0.0 to 1.0
  final String? resultFilePath;
  final int? resultSizeBytes;
  final String? errorMessage;
  final ImageEditOptions? imageOptions;
  final PdfEditOptions? pdfOptions;
  final DateTime createdAt;
  final DateTime? completedAt;

  ConversionJob({
    required this.id,
    required this.sourceFile,
    required this.targetFormat,
    this.status = JobStatus.queued,
    this.progress = 0.0,
    this.resultFilePath,
    this.resultSizeBytes,
    this.errorMessage,
    this.imageOptions,
    this.pdfOptions,
    required this.createdAt,
    this.completedAt,
  });

  ConversionJob copyWith({
    String? id,
    FileItem? sourceFile,
    String? targetFormat,
    JobStatus? status,
    double? progress,
    String? resultFilePath,
    int? resultSizeBytes,
    String? errorMessage,
    ImageEditOptions? imageOptions,
    PdfEditOptions? pdfOptions,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return ConversionJob(
      id: id ?? this.id,
      sourceFile: sourceFile ?? this.sourceFile,
      targetFormat: targetFormat ?? this.targetFormat,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      resultFilePath: resultFilePath ?? this.resultFilePath,
      resultSizeBytes: resultSizeBytes ?? this.resultSizeBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      imageOptions: imageOptions ?? this.imageOptions,
      pdfOptions: pdfOptions ?? this.pdfOptions,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

