import 'package:flutter/material.dart';
// Assuming you will rename/refactor TaskDetailsScreen to CaseDetailsScreen
import '../../Widgets/customapp_bar.dart';
import '../../constants/colors.dart'; // Assuming colors are defined here

// Renamed screen class
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  // Renamed state class
  TasksScreenState createState() => TasksScreenState();
}

// Renamed state class
class TasksScreenState extends State<TasksScreen> {
  // Renamed list and updated data for legal context
  final List<Map<String, dynamic>> cases = [
    {
      "title": "Case #CL-2024-001: Smith v. Corp",
      "description": "Draft motion for summary judgment.",
      "dueDate": "2024-08-15",
      "priority": "High",
      "clientName": "John Smith",
      "caseType": "Civil Litigation",
    },
    {
      "title": "Matter #RE-2024-015: Property Purchase",
      "description": "Review title report and prepare closing documents.",
      "dueDate": "2024-07-30",
      "priority": "Medium",
      "clientName": "Jane Doe",
      "caseType": "Real Estate",
    },
    {
      "title": "Case #IP-2024-003: Patent Application",
      "description": "Respond to USPTO office action.",
      "dueDate": "2024-09-01",
      "priority": "High",
      "clientName": "Innovate Inc.",
      "caseType": "Intellectual Property",
    },
    {
      "title": "Matter #FL-2024-020: Davis Divorce",
      "description": "Client consultation regarding asset division.",
      "dueDate": "2024-07-25",
      "priority": "Low",
      "clientName": "Sarah Davis",
      "caseType": "Family Law",
    },
  ];

  // Renamed method and added parameters for new fields
  void _addCase(
      String title,
      String description,
      String dueDate,
      String priority,
      String clientName,
      String caseType,
      ) {
    setState(() {
      // Add new case with all fields to the 'cases' list
      cases.add({
        "title": title,
        "description": description,
        "dueDate": dueDate,
        "priority": priority,
        "clientName": clientName, // Added field
        "caseType": caseType,     // Added field
      });
    });
  }

  // Renamed method
  void _showAddCaseDialog() {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    final TextEditingController dueDateController = TextEditingController();
    final TextEditingController clientNameController = TextEditingController(); // New controller
    final TextEditingController caseTypeController = TextEditingController();   // New controller
    final List<String> priorities = ['High', 'Medium', 'Low'];
    String selectedPriority = priorities[0]; // Default to High

    // Use a StatefulWidget inside the dialog to handle Dropdown state update
    showDialog(
      context: context,
      builder: (context) {
        // Use StatefulBuilder to manage the dropdown state within the dialog
        return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                // Updated dialog title
                title: const Text(
                  "Add New Case / Matter",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          // Updated label
                          labelText: "Case Name / Number",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField( // New field
                        controller: clientNameController,
                        decoration: const InputDecoration(
                          labelText: "Client Name",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField( // New field
                        controller: caseTypeController,
                        decoration: const InputDecoration(
                          labelText: "Case Type (e.g., Litigation, Real Estate)",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: descriptionController,
                        maxLines: 3, // Allow more space for description
                        decoration: const InputDecoration(
                          // Updated label
                          labelText: "Case Summary / Description",
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: dueDateController,
                        decoration: const InputDecoration(
                          // Updated label
                          labelText: "Deadline / Due Date (YYYY-MM-DD)",
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today), // Added icon hint
                        ),
                        keyboardType: TextInputType.datetime,
                        onTap: () async {
                          // Optional: Show date picker
                          FocusScope.of(context).requestFocus(FocusNode()); // Hide keyboard
                          DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2101),
                          );
                          if (picked != null) {
                            dueDateController.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: "Priority",
                          border: OutlineInputBorder(),
                        ),
                        value: selectedPriority,
                        items: priorities.map((String priority) {
                          return DropdownMenuItem<String>(
                            value: priority,
                            child: Text(priority),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            // Use setDialogState to update the dropdown value
                            setDialogState(() {
                              selectedPriority = newValue;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "Cancel",
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.buttonColor, // Use theme color
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      // Validate all fields including new ones
                      if (titleController.text.isNotEmpty &&
                          descriptionController.text.isNotEmpty &&
                          dueDateController.text.isNotEmpty &&
                          clientNameController.text.isNotEmpty && // Validate new field
                          caseTypeController.text.isNotEmpty) { // Validate new field
                        // Call _addCase with all arguments
                        _addCase(
                          titleController.text,
                          descriptionController.text,
                          dueDateController.text,
                          selectedPriority,
                          clientNameController.text, // Pass new field value
                          caseTypeController.text,   // Pass new field value
                        );
                        Navigator.pop(context);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please fill in all fields'),
                            backgroundColor: Colors.orangeAccent,
                          ),
                        );
                      }
                    },
                    // Updated button text
                    child: const Text("Add Case"),
                  ),
                ],
              );
            }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 19),
        child: FloatingActionButton(
          // Call the renamed dialog method
          onPressed: _showAddCaseDialog,
          backgroundColor: AppColors.buttonColor,
          shape: const CircleBorder(),
          child: const Icon(Icons.add, size: 30, color: Colors.white),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Updated AppBar title
              const CustomAppBar(text: 'Tasks', text1: ''), // Or 'My Matters', etc.
              const SizedBox(height: 20), // Increased spacing
              Expanded(
                child: ListView.builder(
                  // Use the 'cases' list
                  itemCount: cases.length,
                  itemBuilder: (context, index) {
                    // Use 'caseData' variable
                    final caseData = cases[index];
                    IconData priorityIcon;
                    Color priorityColor;

                    switch (caseData['priority']) {
                      case 'High':
                        priorityIcon = Icons.warning_amber_rounded; // More distinct icon
                        priorityColor = Colors.redAccent;
                        break;
                      case 'Medium':
                        priorityIcon = Icons.bolt; // Keep bolt or use flag
                        priorityColor = Colors.orangeAccent;
                        break;
                      case 'Low':
                        priorityIcon = Icons.low_priority; // Specific low priority icon
                        priorityColor = Colors.green;
                        break;
                      default:
                        priorityIcon = Icons.help_outline; // Different default
                        priorityColor = Colors.grey;
                    }

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withAlpha((0.15 * 255).toInt()), // Softer shadow
                            spreadRadius: 1,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      margin: const EdgeInsets.only(bottom: 16), // Increased margin
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Changed icon to gavel
                                Icon(
                                  Icons.gavel, // Legal-themed icon
                                  size: 22,
                                  color: Colors.deepPurple.shade700,
                                ),
                                const SizedBox(width: 10),
                                Expanded( // Ensure title doesn't overflow
                                  child: Text(
                                    // Use caseData
                                    caseData['title'],
                                    style: TextStyle(
                                      fontSize: 17, // Slightly smaller font
                                      fontWeight: FontWeight.bold,
                                      color: Colors.deepPurple.shade900,
                                    ),
                                    overflow: TextOverflow.ellipsis, // Handle long titles
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Display Client Name
                            Row(
                              children: [
                                Icon(
                                  Icons.person_outline, // Client icon
                                  size: 16,
                                  color: Colors.blueGrey,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "Client: ${caseData['clientName']}",
                                    style: const TextStyle(fontSize: 14, color: Colors.blueGrey),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Display Case Type
                            Row(
                              children: [
                                Icon(
                                  Icons.folder_special_outlined, // Case type icon
                                  size: 16,
                                  color: Colors.blueGrey,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "Type: ${caseData['caseType']}",
                                    style: const TextStyle(fontSize: 14, color: Colors.blueGrey),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Updated Description/Summary label
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start, // Align top
                              children: [
                                Icon(
                                  Icons.description_outlined, // Use outlined icon
                                  size: 16,
                                  color: Colors.black54,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    // Updated label and use caseData
                                    "Summary: ${caseData['description']}",
                                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                                    maxLines: 2, // Limit lines shown initially
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Updated Due Date/Deadline label
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined, // Use outlined icon
                                  size: 16,
                                  color: Colors.black54,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  // Updated label and use caseData
                                  "Deadline: ${caseData['dueDate']}",
                                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12), // More spacing before actions
                            Divider(color: Colors.grey.shade200), // Visual separator
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Priority Display
                                Row(
                                  children: [
                                    Icon(
                                      priorityIcon,
                                      size: 18, // Slightly larger icon
                                      color: priorityColor,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      // Use caseData
                                      "Priority: ${caseData['priority']}",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600, // Slightly bolder
                                        color: priorityColor,
                                      ),
                                    ),
                                  ],
                                ),
                                // View Details Button
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.buttonColor.withAlpha((0.1 * 255).toInt()), // Subtle background
                                    foregroundColor: AppColors.buttonColor, // Theme color text
                                    elevation: 0, // No shadow for subtle button
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20), // Pill shape
                                      side: BorderSide(color: AppColors.buttonColor.withAlpha((0.2 * 255).toInt())), // Optional border
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        // Navigate to CaseDetailsScreen (needs to be created/refactored)
                                        // Pass the specific case data
                                        builder: (_) => TasksDetailsScreen(caseData: caseData),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.arrow_forward_ios, size: 12), // Different icon
                                  label: const Text("View Details"),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Placeholder for the details screen - you need to create/refactor this file
// (e.g., timesheetapp/views/cases/casedetails.dart)
class TasksDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> caseData;

  const TasksDetailsScreen({super.key, required this.caseData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(caseData['title'] ?? 'Case Details'),
        backgroundColor: AppColors.buttonColor, // Example color
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView( // Use ListView for potentially long content
          children: [
            Text('Case Details', style: Theme.of(context).textTheme.headlineSmall),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.gavel),
              title: const Text('Case/Matter Name'),
              subtitle: Text(caseData['title'] ?? 'N/A'),
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Client'),
              subtitle: Text(caseData['clientName'] ?? 'N/A'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_special),
              title: const Text('Case Type'),
              subtitle: Text(caseData['caseType'] ?? 'N/A'),
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('Summary/Description'),
              subtitle: Text(caseData['description'] ?? 'N/A'),
              isThreeLine: true, // Allow more space if needed
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Deadline'),
              subtitle: Text(caseData['dueDate'] ?? 'N/A'),
            ),
            ListTile(
              leading: Icon(Icons.warning, color: _getPriorityColor(caseData['priority'])),
              title: const Text('Priority'),
              subtitle: Text(caseData['priority'] ?? 'N/A', style: TextStyle(color: _getPriorityColor(caseData['priority']), fontWeight: FontWeight.bold)),
            ),
            // Add more details or actions (e.g., Edit, Add Note, Upload Document) here
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () { /* TODO: Implement Edit functionality */ },
              icon: const Icon(Icons.edit),
              label: const Text('Edit Case Details'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.buttonColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getPriorityColor(String? priority) {
    switch (priority) {
      case 'High': return Colors.redAccent;
      case 'Medium': return Colors.orangeAccent;
      case 'Low': return Colors.green;
      default: return Colors.grey;
    }
  }
}