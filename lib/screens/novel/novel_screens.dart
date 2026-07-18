import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../controllers/novel_reader_controller.dart';
import '../../models/api_config.dart';
import '../../models/app_character.dart';
import '../../models/app_settings.dart';
import '../../models/chat_message.dart';
import '../../models/chat_summary.dart';
import '../../models/novel_book.dart';
import '../../prompts/prompt_builder.dart';
import '../../services/ai_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/novel_parser.dart';
import '../../services/novel_summary_service.dart';
import '../../utils/app_i18n.dart';
import '../../utils/confirm_dialog.dart';
import '../../utils/page_layout.dart';
import '../../utils/privacy_password_prompt.dart';
import '../../utils/snack.dart';
import '../../utils/stream_text_buffer.dart';
import '../../widgets/app_background.dart';
import '../../widgets/endpoint_picker.dart';
import '../../widgets/message_content.dart';
import '../../widgets/setting_slider.dart';

part 'novel_library_screen.dart';
part 'novel_reader_screen.dart';
part 'widgets/reader_text.dart';
part 'widgets/novel_chat_bubble.dart';
