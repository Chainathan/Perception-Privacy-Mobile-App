import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../models/text_block_with_pii.dart';
import '../models/text_element_with_pii.dart';
import '../services/enhanced_ocr_service.dart';
import '../services/chatgpt_service.dart';
import '../services/text_pii_masking_service.dart';
import '../widgets/document_preview_widget.dart';
import '../widgets/interactive_document_preview.dart';
import '../config/api_keys.dart';
import 'package:perception_privacy_mobile_app/models/pii_entity.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_file/open_file.dart';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;

/// Screen for document preview and PII detection
class DocumentPreviewScreen extends StatefulWidget {
  final File? initialImage;

  const DocumentPreviewScreen({
    Key? key,
    this.initialImage,
  }) : super(key: key);

  @override
  State<DocumentPreviewScreen> createState() => _DocumentPreviewScreenState();
}

class _DocumentPreviewScreenState extends State<DocumentPreviewScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer();
  late final ChatGPTService _chatGptService;
  late final EnhancedOcrService _enhancedOcrService;
  late final TextPIIMaskingService _maskingService;

  File? _selectedImage;
  List<TextBlockWithPII> _textBlocks = [];
  bool _isProcessing = false;
  String _statusMessage = '';
  bool _showBoundingBoxes = true;
  bool _showDetectionInfo = true;
  bool _showAllWords = true;
  Set<PIIEntityType> _selectedPIITypes =
      Set<PIIEntityType>.from(PIIEntityType.values);
  bool _isMasking = false;
  Color _maskColor = Colors.black;
  File? _maskedImage;
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _chatGptService = ChatGPTService(apiKey: ApiKeys.chatGptApiKey);
    _enhancedOcrService = EnhancedOcrService(
      textRecognizer: _textRecognizer,
      chatGptService: _chatGptService,
    );
    _maskingService = TextPIIMaskingService();

    // Set initial image if provided and perform OCR
    if (widget.initialImage != null) {
      _selectedImage = widget.initialImage;
      _performInitialOCR();
    }

    // Check if API key is configured
    if (ApiKeys.chatGptApiKey == 'YOUR_CHATGPT_API_KEY_HERE') {
      _statusMessage =
          'Warning: Please configure your ChatGPT API key in lib/config/api_keys.dart';
    }
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  /// Pick an image from the gallery and perform OCR
  Future<void> _pickImage() async {
    try {
      final pickedFile =
          await _imagePicker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        debugPrint('Image picked: ${pickedFile.path}');
        setState(() {
          _selectedImage = File(pickedFile.path);
          _textBlocks = [];
          _statusMessage = 'Performing OCR...';
          _isProcessing = true;
        });

        try {
          // Perform OCR
          debugPrint('Starting OCR processing...');
          final textBlocks = await _textRecognizer.processImage(
            InputImage.fromFilePath(pickedFile.path),
          );
          debugPrint('OCR completed. Found ${textBlocks.blocks.length} blocks');

          // Convert to our format
          final blocks = textBlocks.blocks.map((block) {
            final elements = block.lines.expand((line) {
              return line.elements.map((element) {
                return TextElementWithPII(
                  element: element,
                  detectedPII: [],
                  isSelected: false,
                  boundingBox: element.boundingBox,
                );
              });
            }).toList();

            // Create a map of word bounding boxes
            final wordBoxes = <String, Rect>{};
            for (final element in elements) {
              wordBoxes[element.text] = element.boundingBox;
            }

            return TextBlockWithPII(
              originalBlock: block,
              lines: block.lines,
              wordBoundingBoxes: wordBoxes,
              elementsWithPII: elements,
              detectedPII: [],
              isSelected: false,
              boundingBox: block.boundingBox,
            );
          }).toList();

          debugPrint('Converted ${blocks.length} blocks to our format');
          setState(() {
            _textBlocks = blocks;
            _isProcessing = false;
            _statusMessage =
                'OCR completed. Found ${blocks.length} text blocks.';
            _showAllWords = true; // Show all words after OCR
          });
        } catch (e) {
          debugPrint('Error performing OCR: $e');
          setState(() {
            _isProcessing = false;
            _statusMessage = 'Error performing OCR: $e';
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error picking image: $e';
      });
    }
  }

  /// Process the selected document for PII detection
  Future<void> _processDocument() async {
    if (_selectedImage == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Processing document for PII...';
      _showAllWords = false; // Hide all words, only show PII after processing
    });

    try {
      debugPrint('Starting PII processing...');
      final textBlocks =
          await _enhancedOcrService.processDocument(_selectedImage!);
      debugPrint(
          'Processing completed. Found ${textBlocks.length} text blocks');

      // Count total PII entities
      final totalPII = textBlocks.fold<int>(
          0, (sum, block) => sum + block.detectedPII.length);
      debugPrint('Total PII entities found: $totalPII');

      setState(() {
        _textBlocks = textBlocks;
        _isProcessing = false;
        _statusMessage =
            'Document processed. Found ${textBlocks.length} text blocks with $totalPII PII entities.';
      });
    } catch (e) {
      debugPrint('Error processing document: $e');
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error processing document: $e';
      });
    }
  }

  /// Handle text block selection
  void _onBlockSelected(TextBlockWithPII block) {
    debugPrint('Block selected: ${block.text}');
    setState(() {
      final index = _textBlocks.indexOf(block);
      if (index != -1) {
        _textBlocks[index] = block.copyWith(isSelected: true);
        debugPrint(
            'Updated block at index $index with ${block.detectedPII.length} PII entities');
      }
    });
  }

  /// Handle text block deselection
  void _onBlockDeselected(TextBlockWithPII block) {
    debugPrint('Block deselected: ${block.text}');
    setState(() {
      final index = _textBlocks.indexOf(block);
      if (index != -1) {
        _textBlocks[index] = block.copyWith(isSelected: false);
        debugPrint(
            'Updated block at index $index with ${block.detectedPII.length} PII entities');
      }
    });
  }

  /// Handle text element selection
  void _onElementSelected(TextElementWithPII element) {
    debugPrint('Element selected: ${element.text}');
    setState(() {
      _textBlocks = _textBlocks.map((block) {
        final updatedElements = block.elementsWithPII.map((e) {
          if (e == element) {
            return e.copyWith(isSelected: true);
          }
          return e;
        }).toList();
        return block.copyWith(elementsWithPII: updatedElements);
      }).toList();
    });
  }

  /// Handle text element deselection
  void _onElementDeselected(TextElementWithPII element) {
    debugPrint('Element deselected: ${element.text}');
    setState(() {
      _textBlocks = _textBlocks.map((block) {
        final updatedElements = block.elementsWithPII.map((e) {
          if (e == element) {
            return e.copyWith(isSelected: false);
          }
          return e;
        }).toList();
        return block.copyWith(elementsWithPII: updatedElements);
      }).toList();
    });
  }

  /// Apply masking to selected elements
  Future<void> _applyMasking() async {
    if (_selectedImage == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Applying masking...';
    });

    try {
      // Get all selected elements
      final selectedElements = _textBlocks
          .expand((block) => block.elementsWithPII)
          .where((element) => element.isSelected)
          .toList();

      if (selectedElements.isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'No elements selected for masking.';
        });
        return;
      }

      // Create a list of blocks containing selected elements
      final blocksToMask = _textBlocks.where((block) {
        return block.elementsWithPII.any((element) => element.isSelected);
      }).toList();

      // Apply masking
      final maskedFile = await _maskingService.maskDocument(
        _selectedImage!,
        blocksToMask,
        _maskColor,
      );

      // Save the masked document
      final savedFile = await _maskingService.saveMaskedDocument(maskedFile);

      setState(() {
        _isProcessing = false;
        _statusMessage = 'Masking completed. Saved to: ${savedFile.path}';
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error applying masking: $e';
      });
    }
  }

  void _togglePIIType(PIIEntityType type) {
    setState(() {
      if (_selectedPIITypes.contains(type)) {
        _selectedPIITypes.remove(type);
      } else {
        _selectedPIITypes.add(type);
      }
    });
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Mask Color'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ColorPicker(
                pickerColor: _maskColor,
                onColorChanged: (color) {
                  setState(() {
                    _maskColor = color;
                  });
                },
                pickerAreaHeightPercent: 0.8,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveMaskedImage() async {
    if (_selectedImage == null || !_isMasking) return;

    try {
      setState(() {
        _isProcessing = true;
        _statusMessage = 'Saving masked image...';
      });

      // Read the image file
      final bytes = await _selectedImage!.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) throw Exception('Failed to decode image');

      // Create a copy of the image to modify
      final maskedImage =
          img.copyResize(image, width: image.width, height: image.height);

      // Get the scaling factors
      final scaleX = image.width / _imageSize!.width;
      final scaleY = image.height / _imageSize!.height;

      // Draw masks for each selected PII type
      for (final block in _textBlocks) {
        for (final element in block.elementsWithPII) {
          if (element.hasPII) {
            final piiType = element.primaryPIIType;
            if (piiType != null && _selectedPIITypes.contains(piiType)) {
              final rect = element.boundingBox;
              final x1 = (rect.left * scaleX).round();
              final y1 = (rect.top * scaleY).round();
              final x2 = (rect.right * scaleX).round();
              final y2 = (rect.bottom * scaleY).round();

              // Draw the mask
              img.fillRect(
                maskedImage,
                x1: x1,
                y1: y1,
                x2: x2,
                y2: y2,
                color: img.ColorRgba8(
                  _maskColor.red,
                  _maskColor.green,
                  _maskColor.blue,
                  _maskColor.alpha,
                ),
              );
            }
          }
        }
      }

      // Get the application documents directory
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'masked_image_$timestamp.png';
      final filePath = '${directory.path}/$fileName';

      // Save the masked image
      final maskedBytes = img.encodePng(maskedImage);
      final maskedFile = File(filePath);
      await maskedFile.writeAsBytes(maskedBytes);

      setState(() {
        _maskedImage = maskedFile;
        _isProcessing = false;
        _statusMessage = 'Image saved successfully: $fileName';
      });

      // Show a snackbar with options to open or share the image
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Image saved successfully'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () async {
              final result = await OpenFile.open(maskedFile.path);
              debugPrint('Open file result: ${result.message}');
            },
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error saving image: $e';
      });
    }
  }

  Future<void> _performInitialOCR() async {
    if (_selectedImage == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Performing OCR...';
    });

    try {
      debugPrint('Starting OCR processing...');
      final textBlocks = await _textRecognizer.processImage(
        InputImage.fromFilePath(_selectedImage!.path),
      );
      debugPrint('OCR completed. Found ${textBlocks.blocks.length} blocks');

      // Convert to our format
      final blocks = textBlocks.blocks.map((block) {
        final elements = block.lines.expand((line) {
          return line.elements.map((element) {
            return TextElementWithPII(
              element: element,
              detectedPII: [],
              isSelected: false,
              boundingBox: element.boundingBox,
            );
          });
        }).toList();

        // Create a map of word bounding boxes
        final wordBoxes = <String, Rect>{};
        for (final element in elements) {
          wordBoxes[element.text] = element.boundingBox;
        }

        return TextBlockWithPII(
          originalBlock: block,
          lines: block.lines,
          wordBoundingBoxes: wordBoxes,
          elementsWithPII: elements,
          detectedPII: [],
          isSelected: false,
          boundingBox: block.boundingBox,
        );
      }).toList();

      debugPrint('Converted ${blocks.length} blocks to our format');
      setState(() {
        _textBlocks = blocks;
        _isProcessing = false;
        _statusMessage = 'OCR completed. Found ${blocks.length} text blocks.';
        _showAllWords = true; // Show all words after OCR
      });
    } catch (e) {
      debugPrint('Error performing OCR: $e');
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error performing OCR: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PII Detection Test'),
        actions: [
          IconButton(
            icon: Icon(
                _showBoundingBoxes ? Icons.visibility : Icons.visibility_off),
            onPressed: () {
              setState(() {
                _showBoundingBoxes = !_showBoundingBoxes;
              });
            },
            tooltip: _showBoundingBoxes
                ? 'Hide Bounding Boxes'
                : 'Show Bounding Boxes',
          ),
          if (_isMasking)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isProcessing ? null : _saveMaskedImage,
              tooltip: 'Save Masked Image',
            ),
        ],
      ),
      body: Column(
        children: [
          // Image preview
          if (_selectedImage != null)
            Expanded(
              flex: 2,
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: InteractiveDocumentPreview(
                    imageFile: _selectedImage!,
                    textBlocks: _textBlocks,
                    maskColor: _maskColor,
                    showBoundingBoxes: _showBoundingBoxes,
                    showAllWords: _showAllWords,
                    selectedPIITypes: _selectedPIITypes,
                    applyMasking: _isMasking,
                    onImageSize: (size) {
                      setState(() {
                        _imageSize = size;
                      });
                    },
                  ),
                ),
              ),
            ),

          // PII Legend
          if (_showBoundingBoxes)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'PII Types',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (_selectedPIITypes.length ==
                                PIIEntityType.values.length) {
                              _selectedPIITypes.clear();
                            } else {
                              _selectedPIITypes =
                                  Set<PIIEntityType>.from(PIIEntityType.values);
                            }
                          });
                        },
                        child: Text(
                          _selectedPIITypes.length ==
                                  PIIEntityType.values.length
                              ? 'Deselect All'
                              : 'Select All',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: PIIEntityType.values.map((type) {
                      return InkWell(
                        onTap: () => _togglePIIType(type),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _selectedPIITypes.contains(type)
                                ? _getPIIColor(type).withOpacity(0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _getPIIColor(type),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: _getPIIColor(type),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                type.toString().split('.').last,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _selectedPIITypes.contains(type)
                                      ? Colors.black
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          // Controls
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    SizedBox(
                      width: 120,
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _pickImage,
                        icon: const Icon(Icons.image, size: 20),
                        label: const Text('Select Image',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ||
                                _selectedImage == null ||
                                _textBlocks.isEmpty
                            ? null
                            : _processDocument,
                        icon: const Icon(Icons.document_scanner, size: 20),
                        label: const Text('Process',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ||
                                _selectedImage == null ||
                                _textBlocks.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  _isMasking = !_isMasking;
                                });
                              },
                        icon: Icon(
                          _isMasking ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                        ),
                        label: Text(
                          _isMasking ? 'Show PII' : 'Mask PII',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isMasking ? Colors.red : null,
                        ),
                      ),
                    ),
                    if (_isMasking)
                      InkWell(
                        onTap: _showColorPicker,
                        child: Container(
                          width: 32,
                          height: 32,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            color: _maskColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Status message
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              _statusMessage,
              style: TextStyle(
                color: _statusMessage.contains('Error') ||
                        _statusMessage.contains('Warning')
                    ? Colors.red
                    : _isProcessing
                        ? Colors.blue
                        : Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Processing indicator
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),

          // Text blocks with PII (collapsible)
          if (_textBlocks.isNotEmpty)
            Column(
              children: [
                // Minimize/Maximize button
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Detection Information',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _showDetectionInfo
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 28,
                        ),
                        onPressed: () {
                          setState(() {
                            _showDetectionInfo = !_showDetectionInfo;
                          });
                        },
                        tooltip: _showDetectionInfo
                            ? 'Hide Detection Info'
                            : 'Show Detection Info',
                      ),
                    ],
                  ),
                ),
                // Detection info content
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: _showDetectionInfo ? 300 : 0,
                  child: DocumentPreviewWidget(
                    textBlocks: _textBlocks,
                    onBlockSelected: _onBlockSelected,
                    onBlockDeselected: _onBlockDeselected,
                    onElementSelected: _onElementSelected,
                    onElementDeselected: _onElementDeselected,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Color _getPIIColor(PIIEntityType piiType) {
    switch (piiType) {
      case PIIEntityType.name:
        return const Color(0xFFFF5252);
      case PIIEntityType.email:
        return const Color(0xFF2196F3);
      case PIIEntityType.phone:
        return const Color(0xFF4CAF50);
      case PIIEntityType.address:
        return const Color(0xFFFF9800);
      case PIIEntityType.ssn:
        return const Color(0xFF9C27B0);
      case PIIEntityType.creditCard:
        return const Color(0xFFE91E63);
      case PIIEntityType.date:
        return const Color(0xFF009688);
      default:
        return const Color(0xFF607D8B);
    }
  }
}
