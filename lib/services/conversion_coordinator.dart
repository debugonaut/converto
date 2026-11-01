import 'dart:async';
import 'dart:io';
import '../models/conversion_job.dart';
import 'converters/base_converter.dart';
import 'converters/document_converter.dart';
import 'converters/image_converter.dart';
import 'converters/pdf_converter.dart';
import 'converters/presentation_converter.dart';
import 'converters/spreadsheet_converter.dart';
import 'history_service.dart';

class ConversionCoordinator {
  static final ConversionCoordinator _instance =
      ConversionCoordinator._internal();
  factory ConversionCoordinator() => _instance;
  ConversionCoordinator._internal() {
    _registerDefaultConverters();
  }

  final List<BaseConverter> _converters = [];
  final List<ConversionJob> _queue = [];
  final _jobsController = StreamController<List<ConversionJob>>.broadcast();
  bool _isProcessing = false;

  Stream<List<ConversionJob>> get queueStream => _jobsController.stream;
  List<ConversionJob> get currentQueue => List.unmodifiable(_queue);

  void _registerDefaultConverters() {
    _converters.addAll([
      ImageConverter(),
      PdfConverter(),
      DocumentConverter(),
      SpreadsheetConverter(),
      PresentationConverter(),
    ]);
  }

  BaseConverter? findConverter(String fromExt, String toExt) {
    for (final converter in _converters) {
      if (converter.canConvert(fromExt, toExt)) {
        return converter;
      }
    }
    return null;
  }

  void addJob(ConversionJob job) {
    _queue.add(job);
    _notify();
    _processNextInQueue();
  }

  void addJobs(List<ConversionJob> jobs) {
    _queue.addAll(jobs);
    _notify();
    _processNextInQueue();
  }

  void removeJob(String jobId) {
    _queue.removeWhere((j) => j.id == jobId);
    _notify();
  }

  void clearCompletedJobs() {
    _queue.removeWhere((j) => j.status == JobStatus.completed);
    _notify();
  }

  Future<void> _processNextInQueue() async {
    if (_isProcessing) return;

    final nextJobIndex = _queue.indexWhere((j) => j.status == JobStatus.queued);
    if (nextJobIndex == -1) return;

    _isProcessing = true;
    var job = _queue[nextJobIndex];

    try {
      // Mark processing
      job = job.copyWith(status: JobStatus.processing, progress: 0.05);
      _queue[nextJobIndex] = job;
      _notify();

      final sourceFile = File(job.sourceFile.path);
      if (!sourceFile.existsSync()) {
        throw Exception('Source file no longer exists at ${sourceFile.path}');
      }

      final converter = findConverter(
        job.sourceFile.extension,
        job.targetFormat,
      );
      if (converter == null) {
        throw Exception(
          'No converter available for .${job.sourceFile.extension} to .${job.targetFormat}',
        );
      }

      final resultFile = await converter.convert(
        sourceFile: sourceFile,
        targetFormat: job.targetFormat,
        imageOptions: job.imageOptions,
        pdfOptions: job.pdfOptions,
        onProgress: (prog) {
          job = job.copyWith(progress: prog);
          _queue[nextJobIndex] = job;
          _notify();
        },
      );

      final resultSize = await resultFile.length();

      // Record in history
      await HistoryService().addRecord(
        HistoryItem(
          id: job.id,
          sourceName: job.sourceFile.name,
          sourcePath: job.sourceFile.path,
          sourceFormat: job.sourceFile.extension,
          targetPath: resultFile.path,
          targetFormat: job.targetFormat,
          fileSizeBytes: resultSize,
          timestamp: DateTime.now(),
        ),
      );

      // Mark completed
      job = job.copyWith(
        status: JobStatus.completed,
        progress: 1.0,
        resultFilePath: resultFile.path,
        resultSizeBytes: resultSize,
        completedAt: DateTime.now(),
      );
      _queue[nextJobIndex] = job;
    } catch (e) {
      job = job.copyWith(
        status: JobStatus.failed,
        errorMessage: e.toString(),
        completedAt: DateTime.now(),
      );
      _queue[nextJobIndex] = job;
    } finally {
      _notify();
      _isProcessing = false;
      // Continue with remaining queue items
      _processNextInQueue();
    }
  }

  void _notify() {
    _jobsController.add(List.unmodifiable(_queue));
  }
}
