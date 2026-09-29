import 'package:flutter/material.dart';

/// Keeps optional chat tools and state in normal flow, without covering messages.
class ChatHeaderPanel extends StatelessWidget {
  const ChatHeaderPanel({
    required this.maxHeight,
    this.tools,
    this.stateCard,
    super.key,
  });

  final double maxHeight;
  final Widget? tools, stateCard;

  @override
  Widget build(BuildContext context) {
    if (tools == null && stateCard == null) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        primary: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [?tools, ?stateCard],
        ),
      ),
    );
  }
}
