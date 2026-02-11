import 'package:flutter/material.dart';
import 'package:pauza_screen_time/pauza_screen_time.dart';

/// Widget for displaying an app in a list with icon, name, packageId, and checkbox.
class AppListTile extends StatelessWidget {
  final AndroidAppInfo app;
  final bool isSelected;
  final VoidCallback onTap;

  const AppListTile({
    super.key,
    required this.app,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: app.icon != null
          ? Image.memory(
              app.icon!,
              width: 48,
              height: 48,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.apps),
            )
          : const Icon(Icons.apps),
      title: Text(app.name),
      subtitle: Text(
        app.packageId.raw,
        style: const TextStyle(fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Checkbox(value: isSelected, onChanged: (_) => onTap()),
      onTap: onTap,
    );
  }
}
