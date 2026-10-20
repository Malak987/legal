import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:legalserviceapp/Widgets/customapp_bar.dart';
import 'package:legalserviceapp/constants/colors.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

// --- UI Constants --- (Added for easier theme management)
const Color primaryColor = AppColors.buttonColor; // Deep Purple variant
const Color accentColor = Color(0xFF009688); // Teal accent
const Color lightBackgroundColor = Color(0xFFF5F5F5); // Lighter grey background
const Color cardBackgroundColor = Colors.white;
const double defaultPadding = 16.0;
const double defaultBorderRadius = 12.0;

class DocumentReviewAI extends StatefulWidget {
  const DocumentReviewAI({super.key});

  @override
  DocumentReviewAIState createState() => DocumentReviewAIState();
}

class DocumentReviewAIState extends State<DocumentReviewAI> {
  // State variables (Unchanged)
  String extractedText = "";
  bool isLoading = false;
  String aiFeedback = "";
  String fileName = "";
  double _uploadProgress = 0.0;

  // File handling methods (Unchanged)
  Future<void> pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'docx'],
        withData: true, // Keep withData if you need the bytes directly elsewhere
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          fileName = result.files.single.name;
          _uploadProgress = 0.0;
          // Clear previous results when a new file is selected
          extractedText = "";
          aiFeedback = "";
          isLoading = true; // Show loading immediately for feedback
        });

        // Simulate upload progress (Visual feedback)
        for (int i = 0; i <= 100; i += 10) {
          await Future.delayed(const Duration(milliseconds: 30)); // Slightly faster
          setState(() => _uploadProgress = i / 100);
        }

        File file = File(result.files.single.path!);
        if (file.path.toLowerCase().endsWith('.pdf')) {
          await extractTextFromPDF(file);
        } else {
          // Assuming other supported types are text-based
          extractedText = await file.readAsString();
          setState(() {}); // Update UI with extracted text
        }

      } else {
        _showErrorSnackbar('File picking cancelled or failed.');
      }
    } catch (e) {
      _showErrorSnackbar('Error picking file: ${e.toString()}');
    } finally {
      // Ensure loading is false if pickFile finishes, unless extraction starts it again
      if (!fileName.isNotEmpty || (fileName.isNotEmpty && extractedText.isNotEmpty)) {
        setState(() => isLoading = false);
      }
      // Reset progress if needed after processing
      if (_uploadProgress == 1.0) {
        await Future.delayed(const Duration(milliseconds: 500)); // Keep progress bar visible briefly
        setState(() => _uploadProgress = 0.0); // Hide progress bar
      }
    }
  }

  Future<void> extractTextFromPDF(File file) async {
    // isLoading should already be true from pickFile
    try {
      final PdfDocument document = PdfDocument(inputBytes: await file.readAsBytes());
      extractedText = PdfTextExtractor(document).extractText();
      document.dispose();
    } catch (e) {
      _showErrorSnackbar('Failed to extract text from PDF: ${e.toString()}');
      extractedText = ""; // Clear text on error
    } finally {
      setState(() => isLoading = false); // Stop loading after extraction attempt
    }
  }

  // AI Analysis methods (Unchanged)
  Future<void> analyzeDocument() async {
    if (extractedText.isEmpty) {
      _showErrorSnackbar("No document text available to analyze.");
      return;
    }
    setState(() => isLoading = true);
    aiFeedback = ""; // Clear previous feedback
    try {
      aiFeedback = await fetchAIResponse(extractedText);
    } catch (e) {
      _showErrorSnackbar('AI analysis failed: ${e.toString()}');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<String> fetchAIResponse(String text) async {
    // IMPORTANT: Hardcoding API keys is insecure. Use environment variables or a secure config service.
    const String apiKey = "AIzaSyCMK7RTPGB2S3YowLkUGh8aYSi4G_bZJsg"; // Replace with your actual key securely
    final Uri url = Uri.parse(
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey"
    );

    final requestBody = jsonEncode({
      "contents": [{
        "parts": [{
          "text": "Analyze the following document professionally. Identify potential risks, ambiguities, or areas needing clarification. Suggest specific edits or clauses for risk mitigation. Structure your response clearly in Markdown format with these sections:\n\n"
              "## Executive Summary:\n[Provide a brief overview of the document's purpose and key findings.]\n\n"
              "## Key Risks & Concerns:\n[Use bullet points to list identified risks, vague language, or potential issues.]\n\n"
              "## Recommended Edits & Mitigations:\n[Provide specific, actionable suggestions for changes or additions to the text. Reference original text snippets if helpful.]\n\n"
              "## Overall Assessment:\n[Give a concluding remark on the document's readiness or areas requiring significant attention.]\n\n"
              "---\n**Document Text:**\n$text" // Ensure clear separation
        }]
      }],
      // Add safety settings and generation config for better control (Optional but Recommended)
      "safetySettings": [
        {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
        {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
        {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
        {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"}
      ],
      "generationConfig": {
        "temperature": 0.7, // Adjust for creativity vs. predictability
        "topK": 1,
        "topP": 1,
        "maxOutputTokens": 2048, // Adjust based on expected response length
      }
    });

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: requestBody,
      ).timeout(const Duration(seconds: 90)); // Add timeout

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        // Safer access to nested JSON structure
        final text = jsonResponse?["candidates"]?[0]?["content"]?["parts"]?[0]?["text"];
        if (text != null) {
          return text;
        } else {
          // Check for blocked content due to safety settings
          final blockReason = jsonResponse?["promptFeedback"]?["blockReason"];
          if (blockReason != null) {
            return "AI response blocked due to safety settings: $blockReason. Please review the document content.";
          }
          return "AI returned an empty response. The document might be too short or lack analyzable content.";
        }
      } else {
        // Try to parse error message from response body
        String errorBody = response.body;
        try {
          final errorJson = jsonDecode(errorBody);
          errorBody = errorJson['error']?['message'] ?? errorBody;
        } catch (_) { /* Ignore if body is not JSON */ }
        throw Exception("API Error (${response.statusCode}): $errorBody");
      }
    } on TimeoutException {
      throw Exception("API request timed out. Please try again.");
    } catch (e) {
      // Rethrow other exceptions for generic handling
      rethrow;
    }
  }

  // Helper methods (Unchanged logic, potentially updated style)
  void _showErrorSnackbar(String message) {
    if (!mounted) return; // Check if the widget is still in the tree
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating, // More modern look
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        margin: const EdgeInsets.all(defaultPadding),
      ),
    );
  }

  // --- Widget Building Methods (UI Focused Enhancements) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(defaultPadding), // Consistent padding
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              CustomAppBar(text: 'Document Review AI', text1: ''),
              SizedBox(height: 10,),
              _buildUploadCard(),
              const SizedBox(height: defaultPadding * 1.5), // Increased spacing
              Expanded(child: _buildContentTabs()),
            ],
          ),
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }


  Card _buildUploadCard() {
    return Card(
      elevation: 3.0, // Slightly softer elevation
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(defaultBorderRadius)),
      color: cardBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(defaultPadding * 1.25), // More internal padding
        child: Column(
          children: [
            // Enhanced Icon
            CircleAvatar(
              radius: 30,
              backgroundColor: primaryColor.withAlpha((0.2 * 255).toInt()),
              child: Icon(Icons.cloud_upload_outlined, size: 32, color: primaryColor),
            ),
            const SizedBox(height: defaultPadding),
            Text(
              "Upload Document for Analysis",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: defaultPadding / 2),
            Text(
              "Supports PDF, TXT, DOCX formats",
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: defaultPadding * 1.5),

            // --- File Name and Progress Section ---
            // Show file name OR upload button
            if (fileName.isEmpty && _uploadProgress == 0.0)
              _buildSelectFileButton()
            else // Show file info and progress
              _buildFileInfoAndProgress(),

            // --- Progress Bar --- (Now inside the File Info section if needed)
            // Kept separate for clarity during upload simulation
            if (_uploadProgress > 0 && _uploadProgress < 1) ...[
              const SizedBox(height: defaultPadding),
              LinearProgressIndicator(
                value: _uploadProgress,
                backgroundColor: Colors.grey[200],
                color: primaryColor, // Use primary color
                minHeight: 6, // Slightly thinner
                borderRadius: BorderRadius.circular(10),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildSelectFileButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : pickFile, // Disable while loading
        icon: const Icon(Icons.upload_file_rounded, size: 20),
        label: Text(
          "Select File",
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor, // Use accent color
          foregroundColor: Colors.white, // Text color
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(defaultBorderRadius),
          ),
          padding: const EdgeInsets.symmetric(vertical: defaultPadding * 0.9), // Adjusted padding
          elevation: 2.0,
        ),
      ),
    );
  }

  Widget _buildFileInfoAndProgress() {
    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.insert_drive_file_rounded, color: primaryColor),
          title: Text(
            fileName,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          subtitle: Text(
            _uploadProgress == 1.0 ? "Ready for analysis" : "Uploading...",
            style: GoogleFonts.poppins(color: Colors.grey[600]),
          ),
          // Add a trailing button to change the file
          trailing: IconButton(
            icon: Icon(Icons.change_circle_outlined, color: Colors.grey[500]),
            tooltip: "Select a different file",
            onPressed: isLoading ? null : pickFile, // Allow changing file if not busy
          ),
          contentPadding: EdgeInsets.zero, // Remove default padding
        ),
        // Optionally, show the progress bar integrated here
        // if (_uploadProgress > 0 && _uploadProgress < 1) ... [ ... Progress Indicator ... ]
      ],
    );
  }


  Widget _buildContentTabs() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4.0), // Padding around the tabs
            decoration: BoxDecoration(
              color: Colors.grey[200], // Background for the tab bar area
              borderRadius: BorderRadius.circular(defaultBorderRadius),
            ),
            child: TabBar(
              labelColor: Colors.white, // Selected text color
              unselectedLabelColor: primaryColor, // Unselected text color
              indicatorSize: TabBarIndicatorSize.tab, // Indicator fills the tab
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(defaultBorderRadius - 4), // Slightly smaller radius
                color: primaryColor, // Indicator color
              ),
              tabs: [
                _buildTab("Document Text", Icons.article_outlined),
                _buildTab("AI Analysis", Icons.auto_awesome_outlined), // Use outlined icons
              ],
            ),
          ),
          const SizedBox(height: defaultPadding), // Space between tabs and content
          Expanded(
            child: TabBarView(
              children: [
                _buildDocumentTextTab(),
                _buildAnalysisTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper for creating styled tabs
  Widget _buildTab(String text, IconData icon) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(
            text,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentTextTab() {
    // Show loading indicator specific to text extraction if needed,
    // but global isLoading often covers this.
    if (isLoading && extractedText.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: primaryColor));
    }

    return Card( // Wrap content in a card for consistency
        elevation: 1.0,
        margin: EdgeInsets.zero, // Let TabBarView handle spacing if needed
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(defaultBorderRadius)),
        color: cardBackgroundColor,
        child: extractedText.isNotEmpty
            ? Padding(
          padding: const EdgeInsets.all(defaultPadding),
          child: SingleChildScrollView(
            child: SelectableText( // Good for copying text
              extractedText,
              style: GoogleFonts.robotoSlab(fontSize: 15, height: 1.5, color: Colors.black87), // Use a readable slab serif
            ),
          ),
        )
            : _buildEmptyState(
          icon: Icons.description_outlined,
          message: "Upload a document to view its text here.",
          buttonText: "Select File",
          onButtonPressed: pickFile,
        )
    );
  }


  Widget _buildAnalysisTab() {
    // Show loading indicator specifically when AI analysis is running
    if (isLoading && aiFeedback.isEmpty && extractedText.isNotEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: primaryColor),
            SizedBox(height: defaultPadding),
            Text("AI is analyzing...", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }


    return Card( // Wrap content in a card
        elevation: 1.0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(defaultBorderRadius)),
        color: cardBackgroundColor,
        child: aiFeedback.isNotEmpty
            ? Padding(
          padding: const EdgeInsets.all(defaultPadding),
          child: SingleChildScrollView(
            child: SelectableText( // Make feedback selectable
              aiFeedback,
              // Consider using flutter_markdown package here for proper rendering
              style: GoogleFonts.poppins(fontSize: 15, height: 1.5, color: Colors.black87),
            ),
          ),
        )
            : _buildEmptyState(
          icon: Icons.auto_awesome_motion_outlined, // Engaging icon
          message: extractedText.isEmpty
              ? "Upload and extract text first."
              : "Run analysis to see AI feedback.",
          buttonText: "Analyze Document",
          // Only enable button if text is ready and not loading
          onButtonPressed: (extractedText.isNotEmpty && !isLoading) ? analyzeDocument : null,
        )
    );
  }


  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    String? buttonText, // Optional button
    VoidCallback? onButtonPressed, // Action for the button
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(defaultPadding * 2), // More padding for empty state
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center, // Center horizontally
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]), // Larger icon
            const SizedBox(height: defaultPadding),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.grey[600], // Slightly darker grey
              ),
            ),
            if (buttonText != null) ...[
              const SizedBox(height: defaultPadding * 1.5),
              ElevatedButton(
                onPressed: onButtonPressed, // Use the provided callback
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor, // Use accent color
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(defaultBorderRadius),
                  ),
                  padding: const EdgeInsets.symmetric(
                      vertical: defaultPadding * 0.8, horizontal: defaultPadding * 1.5),
                ),
                child: Text(
                  buttonText,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget? _buildFloatingActionButton() {
    // Show FAB only if text is ready AND feedback is not yet generated AND not currently loading
    if (extractedText.isNotEmpty && aiFeedback.isEmpty && !isLoading) {
      return FloatingActionButton.extended(
        onPressed: analyzeDocument,
        backgroundColor: accentColor, // Use accent color
        foregroundColor: Colors.white,
        icon: const Icon(Icons.auto_awesome_rounded), // Rounded icon
        label: Text(
          "Analyze Now",
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600), // Bolder text
        ),
        elevation: 4.0, // Standard elevation
      );
    }
    // Don't show FAB otherwise
    return null;
  }
}