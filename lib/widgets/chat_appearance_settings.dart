import 'package:flutter/material.dart';

import '../models/chat_appearance.dart';
import 'chat_bubble_preset_picker.dart';
import 'setting_slider.dart';

List<Widget> chatAppearanceSettings<T extends ChatAppearance<T>>({
  required T draft,
  required ValueChanged<T> preview,
  required ValueChanged<T> apply,
  required double roleOpacity,
  required double userOpacity,
  String keyPrefix = 'chat',
  String roleTitle = '角色气泡',
  double height = 32,
  double displayWidth = 48,
}) {
  Widget slider(
    String id,
    String label,
    double value,
    T Function(double) update, {
    bool background = false,
  }) {
    return (background ? SettingSlider.opacity : SettingSlider.transparency)(
      key: ValueKey('$keyPrefix-$id-setting'),
      label: label,
      opacity: value,
      onChanged: (value) => preview(update(value)),
      onChangeEnd: (value) => apply(update(value)),
      height: height,
      displayWidth: displayWidth,
    );
  }

  Widget bubble(bool user) => ChatBubblePresetSelectionTile(
    key: ValueKey('$keyPrefix-${user ? 'user' : 'role'}-bubble-preset-setting'),
    title: user ? '我的气泡' : roleTitle,
    presetId: user ? draft.userBubblePresetId : draft.roleBubblePresetId,
    isUser: user,
    onChanged: (value) => apply(
      user
          ? draft.copyWith(
              userBubblePresetId: value,
              clearUserBubbleOpacity: true,
            )
          : draft.copyWith(
              roleBubblePresetId: value,
              clearRoleBubbleOpacity: true,
            ),
    ),
  );

  return [
    slider(
      'background-transparency',
      '背景图透明度',
      draft.backgroundImageOpacity,
      (v) => draft.copyWith(backgroundImageOpacity: v),
      background: true,
    ),
    SettingSlider(
      label: '背景图模糊度',
      value: draft.backgroundBlur,
      min: 0,
      max: 12,
      divisions: 12,
      display: draft.backgroundBlur.toStringAsFixed(0),
      onChanged: (v) => preview(draft.copyWith(backgroundBlur: v)),
      onChangeEnd: (v) => apply(draft.copyWith(backgroundBlur: v)),
      height: height,
      displayWidth: displayWidth,
    ),
    slider(
      'top-bar-transparency',
      '顶部状态栏透明度',
      draft.topBarOpacity,
      (v) => draft.copyWith(topBarOpacity: v),
    ),
    slider(
      'input-opacity',
      '输入框透明度',
      draft.inputOpacity,
      (v) => draft.copyWith(inputOpacity: v),
    ),
    bubble(false),
    slider(
      'role-bubble-transparency',
      '角色气泡透明度',
      roleOpacity,
      (v) => draft.copyWith(roleBubbleOpacity: v),
    ),
    bubble(true),
    slider(
      'user-bubble-transparency',
      '我的气泡透明度',
      userOpacity,
      (v) => draft.copyWith(userBubbleOpacity: v),
    ),
  ];
}
