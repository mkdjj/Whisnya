part of '../theater_screens.dart';

class _TheaterTypingBubble extends StatelessWidget {
  const _TheaterTypingBubble({required this.appearance, this.chatTextColor});

  final ChatBubbleAppearance appearance;
  final int? chatTextColor;

  @override
  Widget build(BuildContext context) {
    return ChatBubble(
      isUser: false,
      appearance: appearance,
      fallbackTextColor: chatTextColor,
      child: const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}
