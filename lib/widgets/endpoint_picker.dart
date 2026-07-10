import 'package:flutter/material.dart';

import '../models/api_config.dart';
import '../utils/app_i18n.dart';

Future<String?> showEndpointPicker({
  required BuildContext context,
  required List<AiEndpointConfig> endpoints,
  required String selectedId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        children: [
          ListTile(
            title: Text(
              context.t('选择模型'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final endpoint in endpoints)
            ListTile(
              leading: const Icon(Icons.memory_outlined),
              title: Text(endpoint.name),
              subtitle: Text(endpoint.model),
              trailing: endpoint.id == selectedId
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(context).pop(endpoint.id),
            ),
        ],
      ),
    ),
  );
}
