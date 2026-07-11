part of '../theater_screens.dart';

class _TheaterSessionAvatar extends StatelessWidget {
  const _TheaterSessionAvatar({required this.avatar, required this.title});

  final String avatar;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (avatar.isNotEmpty) {
      return CircleAvatar(
        backgroundImage: FileImage(File(avatar)),
        onBackgroundImageError: (_, _) {},
      );
    }
    return CircleAvatar(
      child: Text(title.trim().isEmpty ? '?' : title.trim().characters.first),
    );
  }
}

class _TheaterAvatar extends StatelessWidget {
  const _TheaterAvatar({required this.participant, required this.name});

  final TheaterParticipant? participant;
  final String name;

  @override
  Widget build(BuildContext context) {
    final avatar = participant?.avatar ?? '';
    if (avatar.isNotEmpty) {
      return CircleAvatar(
        radius: 14,
        backgroundImage: FileImage(File(avatar)),
        onBackgroundImageError: (_, _) {},
      );
    }
    return CircleAvatar(
      radius: 14,
      child: Text(name.trim().isEmpty ? '?' : name.trim().characters.first),
    );
  }
}
