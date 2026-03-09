import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/agent_controller.dart';

class HomeScreen extends StatefulWidget {
  final AgentController controller;

  const HomeScreen({super.key, required this.controller});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _apiKeyController = TextEditingController();

  bool _isAccessibilityEnabled = false;
  bool _isCheckingAccessibility = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    widget.controller.addListener(_onControllerUpdate);
    _loadApiKey();
    
    _checkAccessibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAccessibility();
    }
  }

  Future<void> _checkAccessibility() async {
    if (mounted && !_isCheckingAccessibility) {
      setState(() => _isCheckingAccessibility = true);
    }
    
    final isEnabled = await widget.controller.screenCapture.isAccessibilityEnabled();
    
    if (mounted) {
      setState(() {
        _isAccessibilityEnabled = isEnabled;
        _isCheckingAccessibility = false;
      });
    }
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('gemini_api_key');
    if (key != null && key.isNotEmpty) {
      _apiKeyController.text = key;
      widget.controller.configureAi(key);
    }
  }

  Future<void> _saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key);
    widget.controller.configureAi(key);
  }

  void _onControllerUpdate() {
    setState(() {});
    if (widget.controller.isActive &&
        widget.controller.state == AgentState.listening) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }

    // Scroll to bottom on new messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _scrollController.dispose();
    _apiKeyController.dispose();
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isCheckingAccessibility) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAccessibilityEnabled) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: const Text('Access Required'),
          backgroundColor: colorScheme.surface,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.accessibility_new,
                  size: 72,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Accessibility Required',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'To use this app, you must enable the Lucy accessibility service.\n\n'
                  'Go to Settings → Accessibility → Lucy → Enable',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: colorScheme.onSurface.withOpacity(0.7),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => widget.controller.screenCapture.openAccessibilitySettings(),
                  icon: const Icon(Icons.settings),
                  label: const Text('Open Settings'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.controller.isActive
                    ? Colors.greenAccent
                    : Colors.grey,
                boxShadow: widget.controller.isActive
                    ? [
                        BoxShadow(
                          color: Colors.greenAccent.withOpacity(0.5),
                          blurRadius: 8,
                          spreadRadius: 2,
                        )
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Lucy'),
          ],
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.key),
            tooltip: 'API Key',
            onPressed: () => _showApiKeyDialog(context),
          ),
          if (widget.controller.conversation.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear conversation',
              onPressed: () => widget.controller.clearConversation(),
            ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          _buildStatusBar(colorScheme),

          // Conversation list
          Expanded(
            child: widget.controller.conversation.isEmpty
                ? _buildEmptyState(colorScheme)
                : _buildConversationList(colorScheme),
          ),

          // Current transcript
          if (widget.controller.currentTranscript?.isNotEmpty == true)
            _buildTranscriptBar(colorScheme),

          // Bottom bar with mic button
          _buildBottomBar(colorScheme),
        ],
      ),
    );
  }

  Widget _buildStatusBar(ColorScheme colorScheme) {
    final stateIcon = _getStateIcon();
    final statusColor = _getStatusColor();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(color: statusColor.withOpacity(0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(stateIcon, size: 16, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.controller.statusMessage,
              style: TextStyle(
                color: statusColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (!widget.controller.aiService.isConfigured)
            TextButton.icon(
              onPressed: () => _showApiKeyDialog(context),
              icon: Icon(Icons.warning_amber, size: 16, color: Colors.amber),
              label: Text('Set API Key', style: TextStyle(color: Colors.amber, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility,
              size: 72,
              color: colorScheme.primary.withOpacity(0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationList(ColorScheme colorScheme) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: widget.controller.conversation.length,
      itemBuilder: (context, index) {
        final entry = widget.controller.conversation[index];
        return _buildConversationBubble(entry, colorScheme);
      },
    );
  }

  Widget _buildConversationBubble(ConversationEntry entry, ColorScheme colorScheme) {
    final isUser = entry.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser
              ? colorScheme.primary.withOpacity(0.2)
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
          ),
          border: Border.all(
            color: isUser
                ? colorScheme.primary.withOpacity(0.3)
                : colorScheme.outline.withOpacity(0.1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUser ? Icons.person : Icons.smart_toy,
                  size: 14,
                  color: isUser ? colorScheme.primary : colorScheme.secondary,
                ),
                const SizedBox(width: 6),
                Text(
                  isUser ? 'You' : 'Lucy',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isUser ? colorScheme.primary : colorScheme.secondary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Screenshot preview
            if (entry.screenshotPath != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(entry.screenshotPath!),
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 60,
                    color: Colors.grey[800],
                    child: const Center(
                      child: Icon(Icons.broken_image, size: 24),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            SelectableText(
              entry.text,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscriptBar(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(0.05),
        border: Border(
          top: BorderSide(color: colorScheme.primary.withOpacity(0.2)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.controller.currentTranscript ?? '',
              style: TextStyle(
                color: colorScheme.primary,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outline.withOpacity(0.1)),
        ),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Left area: Screenshot button
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: widget.controller.isActive
                    ? IconButton(
                        onPressed: _manualCapture,
                        icon: const Icon(Icons.camera_alt_outlined),
                        tooltip: 'Capture screen now',
                      )
                    : const SizedBox.shrink(),
              ),
            ),

            // Main mic button
            ScaleTransition(
              scale: widget.controller.state == AgentState.listening
                  ? _pulseAnimation
                  : const AlwaysStoppedAnimation(1.0),
              child: GestureDetector(
                onTap: () => widget.controller.toggleAgent(),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: widget.controller.isActive
                          ? [Colors.redAccent, Colors.red[700]!]
                          : [colorScheme.primary, colorScheme.tertiary],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (widget.controller.isActive
                                ? Colors.redAccent
                                : colorScheme.primary)
                            .withOpacity(0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.controller.isActive ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),

            // Right area: Last screenshot preview
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: widget.controller.lastScreenshotPath != null
                    ? GestureDetector(
                        onTap: () => _showScreenshotPreview(context),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: Image.file(
                              File(widget.controller.lastScreenshotPath!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 20),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getStateIcon() {
    switch (widget.controller.state) {
      case AgentState.idle:
        return Icons.mic_off;
      case AgentState.listening:
        return Icons.mic;
      case AgentState.capturing:
        return Icons.camera;
      case AgentState.analyzing:
        return Icons.psychology;
      case AgentState.speaking:
        return Icons.volume_up;
      case AgentState.waitingConfirmation:
        return Icons.help_outline;
      case AgentState.executingAction:
        return Icons.flash_on;
    }
  }

  Color _getStatusColor() {
    switch (widget.controller.state) {
      case AgentState.idle:
        return Colors.grey;
      case AgentState.listening:
        return Colors.greenAccent;
      case AgentState.capturing:
        return Colors.amber;
      case AgentState.analyzing:
        return Colors.blue;
      case AgentState.speaking:
        return Colors.purple;
      case AgentState.waitingConfirmation:
        return Colors.orange;
      case AgentState.executingAction:
        return Colors.cyan;
    }
  }

  void _showApiKeyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gemini API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your Google Gemini API key to enable real AI vision analysis.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiKeyController,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'AIza...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final key = _apiKeyController.text.trim();
              if (key.isNotEmpty) {
                _saveApiKey(key);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _manualCapture() async {
    final path = await widget.controller.screenCapture.captureScreen();
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Screenshot saved: ${path.split('/').last}')),
      );
    }
  }

  void _showScreenshotPreview(BuildContext context) {
    final path = widget.controller.lastScreenshotPath;
    if (path == null) return;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: const Text('Last Screenshot'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Could not load screenshot'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
