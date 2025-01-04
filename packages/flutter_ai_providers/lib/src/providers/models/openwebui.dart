import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:uuid/v4.dart';

/// Internal open-webui json encoder / decoder
/// Encode a request to the open-webui API.
class OwuiCompletionRequest {
  final String model;
  final String? chatId;
  final String? sessionId;
  final String? id;
  final Map<String, bool> features;
  final List<String> toolIds;
  final List<OwuiChatMessage> messages;
  final Map<String, bool> backgroundTasks;

  /// Creates an instance of [OwuiCompletionRequest].
  ///
  /// [model] is the model to be used for the chat.
  /// [messages] is the list of messages in the chat history.
  /// [files] files to be attached to the next request.
  /// [images] images to be attached to the next request.
  OwuiCompletionRequest({
    required this.model,
    required this.messages,
    this.features = const {},
    this.toolIds = const [],
    this.id,
    this.chatId,
    this.sessionId,
    this.backgroundTasks = const {},
  });

  /// Converts the [OwuiCompletionRequest] instance to a JSON object.
  Map<String, dynamic> toJson() {
    final res= {
      'model': model,
      'stream': true,
      'chat_id': chatId,
      'id': id,
      'messages': messages.map((message) => message.toCompletionJson()).toList(),
      'features': features,
      'session_id': sessionId,
      'background_tasks': backgroundTasks,
      'tool_ids': toolIds,
      'files': messages.expand((message) => message.files).map((file) => file.toJson()).toList(),
    };
    return res;
  }

  String toJsonString() => jsonEncode(toJson());
}

/// Internal open-webui json encoder / decoder
/// Decode a chat response from the open-webui API.
class OwuiChatCompletionEvent {
  final List<OwuiChatResponseChoice>? choices;
  final bool done;
  final List? sources;

  /// Creates an instance of [OwuiChatCompletionEvent].
  ///
  /// [choices] is the list of choices in the response.
  OwuiChatCompletionEvent({
    required this.done,
    this.choices,
    this.sources,
  });

  /// Creates an instance of [OwuiChatCompletionEvent] from a JSON object.
  factory OwuiChatCompletionEvent.fromJson(Map<String, dynamic> json) {
    return OwuiChatCompletionEvent(
      sources: json['sources'],
      done: json['done'] ?? false,
      choices: (json['choices'] as List?)?.map((choice) => OwuiChatResponseChoice.fromJson(choice)).toList(),
    );
  }
}

/// Internal open-webui json encoder / decoder
/// Decoder for the choice part of [OwuiChatCompletionEvent].
class OwuiChatResponseChoice {
  final String? content;
  final int? index;
  final dynamic longprobs; // whats type is this?
  final dynamic finishRead; // what type is this?
  

  /// Creates an instance of [OwuiChatResponseChoice].
  ///
  /// [message] is the message in the choice.
  OwuiChatResponseChoice({
    this.content,
    this.index,
    this.longprobs,
    this.finishRead,
  });

  /// Creates an instance of [OwuiChatResponseChoice] from a JSON object.
  factory OwuiChatResponseChoice.fromJson(Map<String, dynamic> json) {
    return OwuiChatResponseChoice(
      content: json['delta']?['content'],
      index: json['index'],
      longprobs: json['longprobs'],
      finishRead: json['finishRead'],
    );
  }
}

/// Internal open-webui json encoder / decoder
class OwuiImageAttachment {
  final String type;
  final Map<String, String> imageUrl;
  final String name;

  OwuiImageAttachment({
    required this.type,
    required this.imageUrl,
    required this.name,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'image_url': imageUrl,
    'name': name,
  };

  factory OwuiImageAttachment.fromImageAttachment(ImageFileAttachment attachment) {
    final base64Image = base64Encode(attachment.bytes);
    return OwuiImageAttachment(
      type: 'image_url',
      imageUrl: {'url': "data:${attachment.mimeType};base64,$base64Image"},
      name: attachment.name,
    );
  }
}

/// Internal open-webui json encoder / decoder
class OwuiFileAttachment {
  final String? id;

  final String? userId;
  final String? hash;
  final String? filename;
  final Map<String, dynamic>? data;
  final Map<String, dynamic>? meta;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final Map<String, dynamic>? file;
  final String? url;
  final String? collectionName;
  final String? status;
  final int? size;
  final String? error;
  final String? itemId;
  final String? name;
  final String? contentType;
  final String? type;


  OwuiFileAttachment({
    this.id,
    this.hash,
    this.filename,
    this.data,
    this.meta,
    this.createdAt,
    this.updatedAt,
    this.userId,
    this.collectionName,
    this.error,
    this.file,
    this.itemId,
    this.size,
    this.status,
    this.url,
    this.name,
    this.contentType,
    this.type,
  });

  Map<String, dynamic> toJson() => {
    if(id != null) 'id': id,
    if(userId != null)'user_id': userId,
    if(hash != null) 'hash': hash,
    if(filename != null) 'filename': filename,
    if(data != null) 'data': data,
    if(meta != null) 'meta': meta,
    if(createdAt != null) 'created_at': createdAt!.millisecondsSinceEpoch ~/ 1000,
    if(updatedAt != null) 'updated_at': updatedAt!.millisecondsSinceEpoch ~/ 1000,
    if(collectionName != null) 'collection_name': collectionName,
    if(error != null) 'error': error,
    if(file != null) 'file': file,
    if(itemId != null) 'item_id': itemId,
    if(size != null) 'size': size,
    if(status != null) 'status': status,
    if(url != null) 'url': url,
    if(name != null) 'name': name,
    if(contentType != null) 'content_type': contentType,
    if(type != null) 'type': type,

  };

  factory OwuiFileAttachment.fromJson(Map<String, dynamic> json) {
    return OwuiFileAttachment(
      id: json['id'],
      userId: json['user_id'],
      hash: json['hash'],
      filename: json['filename'],
      data: json['data'],
      meta: json['meta'],
      createdAt: json['created_at'] is num ? DateTime.fromMillisecondsSinceEpoch(json['created_at'] * 1000) : null,
      updatedAt: json['updated_at'] is num ? DateTime.fromMillisecondsSinceEpoch(json['updated_at'] * 1000) : null,
      collectionName: json['meta']?['collection_name'],
      contentType: json['meta']?['content_type'],
      name: json['meta']?['name'],
      size: json['meta']?['size'],
      error: json['error'],
      file: json['file'],
      itemId: json['item_id'],
      status: json['status'],
      url: json['url'],
      type: json['type'],
    );
  }
}

class OwuiCitationData {
  final List<String> document;
  final List<Map<String, String>> metadata;
  final Map<String, String> source;

  OwuiCitationData({
    required this.document,
    required this.metadata,
    required this.source,
  });

  factory OwuiCitationData.fromJson(Map<String, dynamic> json) {
    return OwuiCitationData(
      document: List<String>.from(json['document']),
      metadata: List<Map<String, String>>.from(json['metadata'].map((item) => Map<String, String>.from(item))),
      source: Map<String, String>.from(json['source']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'document': document,
      'metadata': metadata,
      'source': source,
    };
  }
}

class OwuiChatList {
  final List<OwuiChatListEntry> chats;

  OwuiChatList({required this.chats});

  factory OwuiChatList.fromJson(List<dynamic> json) {
    return OwuiChatList(
      chats: json.map((entry) => OwuiChatListEntry.fromJson(entry)).toList(),
    );
  }

  List<Map<String, dynamic>> toJson() {
    return chats.map((entry) => entry.toJson()).toList();
  }
}

class OwuiChatListEntry {
  final String id;
  final String title;
  final DateTime updatedAt;
  final DateTime createdAt;

  OwuiChatListEntry({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.createdAt,
  });

  factory OwuiChatListEntry.fromJson(Map<String, dynamic> json) {
    return OwuiChatListEntry(
      id: json['id'],
      title: utf8.decode(json['title'].runes.toList()), // Ensure proper decoding
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updated_at'] * 1000),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] * 1000),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': utf8.encode(title), // Ensure proper encoding
      'updated_at': updatedAt.millisecondsSinceEpoch ~/ 1000,
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
    };
  }
}

class OwuiChat {
  final String? id;
  final String? userId;
  String? title; // meh
  // final List<OwuiChatMessage> messages; // use the messages getter instead...
  final DateTime updatedAt;
  final DateTime createdAt;
  final String? shareId;
  final bool archived;
  final bool pinned;
  final Map<String, dynamic> meta;
  final String? folderId;
  String historyCurrentId; // also meh
  final Map<String, OwuiChatMessage> history;
  final List<String>? models;
  final List<OwuiFileAttachment> historyFiles;

  OwuiChat({
    this.id,
    this.userId,
    this.title,
    // required this.messages,
    DateTime? updatedAt,
    DateTime? createdAt,
    this.shareId,
    this.archived = false,
    this.pinned = false,
    this.meta = const {},
    this.folderId,
    Map<String, OwuiChatMessage>? history,
    List<OwuiFileAttachment>? historyFiles,
    this.historyCurrentId = "",
    this.models,
  }) : 
    history = history ?? {}, // non-const
    historyFiles = historyFiles ?? [], // non-const
    createdAt = createdAt ?? DateTime.now(),
    updatedAt = updatedAt ?? DateTime.now();

  List<OwuiChatMessage> get messages {
    List<OwuiChatMessage> orderedMessages = [];
    OwuiChatMessage? currentMessage = history[historyCurrentId];

    while (currentMessage != null) {
      orderedMessages.add(currentMessage);
      currentMessage = history[currentMessage.parentId];
    }

    return orderedMessages.reversed.toList();
  }

  OwuiChatMessage? get tail {
    return messages.isNotEmpty ? messages.last : null;
  }

  void appendMessage (OwuiChatMessage message) {
    tail?.childrenIds.add(message.id);
    history[message.id] = message;
    historyCurrentId = message.id;
  }

  factory OwuiChat.fromJson(Map<String, dynamic> json, {List<String>? models}) {
    return OwuiChat(
      id: json['id'],
      userId: json['user_id'],
      title: utf8.decode(json['title'].runes.toList()), // Ensure proper decoding
      // messages: chat, // use the messages getter instead...
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updated_at'] * 1000),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] * 1000),
      shareId: json['share_id'],
      archived: json['archived'],
      pinned: json['pinned'],
      meta: json['meta'],
      folderId: json['folder_id'],
      historyFiles: (json['chat']?['files'] as List?)?.map((file) => OwuiFileAttachment.fromJson(file)).toList() ?? [],
      historyCurrentId: json['chat']?['history']?['currentId'],
      models: models ?? (json['models'] is List<String> ? json['models'].cast<String>() : []),
      history: {
        if(json['chat']?['history']?['messages'] is Map<String, dynamic>)
          for(final entry in json['chat']['history']['messages'].entries)
            entry.key: OwuiChatMessage.fromJson(entry.value)
      }
    );
  }

  Map<String, dynamic> toJson({List<String>? models}) {
    return {
      'chat' : {
        'params': {},
        'models': models ?? this.models ?? [],
        'files': historyFiles.map((file) => file.toJson()).toList(),
        'history': {
          'currentId': historyCurrentId,
          'messages': history.map((id, message) => MapEntry(id, message.toJson())),
        },
        'messages': messages.map((message) => message.toJson()).toList(),
      }
    };
  }
}

class OwuiChatMessage extends ChatMessage {
  final String id;
  final String? parentId;
  late final List<String> childrenIds; // MEH
  final DateTime timestamp;
  final List<String>? models;
  final String? model;
  final int? modelIdx;
  final String? modelName;
  bool? done;
  final List<OwuiFileAttachment> files;

  OwuiChatMessage({
    String? id,
    this.parentId,
    this.childrenIds = const [],
    required super.origin,
    super.text,
    DateTime? timestamp,
    super.attachments = const [],
    this.models,
    this.model,
    this.modelIdx,
    this.modelName,
    this.files = const [],
    this.done
  }): id = id ?? UuidV4().generate(), timestamp = timestamp ?? DateTime.now();

  factory OwuiChatMessage.llm({
    String? parentId,
    String? model,
    int? modelIdx,
    String? modelName,
    bool done = false
  }) {
    return OwuiChatMessage(
      parentId: parentId,
      childrenIds: [],
      origin: MessageOrigin.llm,
      text: null,
      timestamp: DateTime.now(),
      models: null,
      model: model,
      modelIdx: modelIdx,
      modelName: modelName,
      done: done,
    );
  }

  factory OwuiChatMessage.user(String text, {
    required Iterable<Attachment> attachments,
    List<String>? models,
    List<OwuiFileAttachment> files = const [],
    String? parentId
  }) {
    return OwuiChatMessage(
      parentId: parentId,
      attachments: attachments,
      childrenIds: [],
      origin: MessageOrigin.user,
      text: text,
      files: files,
      timestamp: DateTime.now(),
      models: models,
      model: null,
    );
  }

  factory OwuiChatMessage.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return OwuiChatMessage(
        parentId: null,
        childrenIds: [],
        origin: MessageOrigin.user,
        text: null,
        timestamp: DateTime.now(),
        models: null,
      );
    }

    final files = (json['files'] as List?)?.map((file) => OwuiFileAttachment.fromJson(file)).toList() ?? [];

    return OwuiChatMessage(
      id: json['id'],
      parentId: json['parentId'],
      childrenIds: List<String>.from(json['childrenIds'] ?? []),
      origin: json['role'] == 'user' ? MessageOrigin.user : MessageOrigin.llm,
      text: json['content'] == null || json['content'] == '' ? null : utf8.decode((json['content']).runes.toList()),
      timestamp: DateTime.fromMillisecondsSinceEpoch((json['timestamp'] ?? 0) * 1000),
      models: List<String>.from(json['models'] ?? []),
      attachments: files.map((file) {
        if (file.type == 'image_url') {
          return ImageFileAttachment(
            name: file.name ?? "",
            mimeType: file.contentType ?? 'image/png',
            bytes: Uint8List.fromList([]),
          );
        } else {
          return FileAttachment.fileOrImage(
            name: file.name ?? "",
            mimeType: file.contentType ?? 'application/octet-stream',
            bytes: Uint8List.fromList([]),
          );
        }
      }).toList(),
      done: json['done'],
      files: files,
      model: json['model'],
      modelIdx: json['modelIdx'],
      modelName: json['modelName'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parentId': parentId,
      'childrenIds': childrenIds,
      'role': origin == MessageOrigin.user ? 'user' : 'assistant',
      'content': text,
      'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
      'files': files.map((file) => file.toJson()).toList(),
      if(model != null) 'model': model,
      if(models != null) 'models': models,
      if(modelIdx != null) 'modelIdx': modelIdx,
      if(modelName != null) 'modelName': modelName,
      if(origin == MessageOrigin.llm) 'userContext': null,
      if(origin == MessageOrigin.llm && done == true) 'done': done,
    };
  }

  Map<String, dynamic> toCompletedJson() {
    return {
      'role': origin == MessageOrigin.user ? 'user' : 'assistant',
      'content': text,
    };
  }

  Map<String, dynamic> toCompletionJson() {
    return {
      'role': origin == MessageOrigin.user ? 'user' : 'assistant',
      'content': text,
    };
  }
}

class OwuiLlmModel {
  final String id;
  final String name;
  final String ownedBy;
  final String? description;
  final OwuiLlmModelInfo? info;
  final bool? arena;
  final int? created;
  final bool? isActive;
  final String? object;
  final bool? preset;
  final List<dynamic>? actions;

  OwuiLlmModel({
    required this.id,
    required this.name,
    required this.ownedBy,
    this.description,
    this.info,
    this.arena,
    this.created,
    this.isActive,
    this.object,
    this.preset,
    this.actions,
  });

  factory OwuiLlmModel.fromJson(Map<String, dynamic> json) {
    return OwuiLlmModel(
      id: json['id'],
      name: json['name'],
      ownedBy: json['owned_by'],
      description: json['info']?['meta']?['description'],
      info: json['info'] != null ? OwuiLlmModelInfo.fromJson(json['info']) : null,
      arena: json['arena'],
      created: json['created'],
      isActive: json['is_active'],
      object: json['object'],
      preset: json['preset'],
      actions: json['actions'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'owned_by': ownedBy,
      if (description != null) 'description': description,
      if (info != null) 'info': info!.toJson(),
      if (arena != null) 'arena': arena,
      if (created != null) 'created': created,
      if (isActive != null) 'is_active': isActive,
      if (object != null) 'object': object,
      if (preset != null) 'preset': preset,
      if (actions != null) 'actions': actions,
    };
  }
}

class OwuiLlmModelInfo {
  final String? id;
  final String? userId;
  final String? baseModelId;
  final String? name;
  final OwuiLlmModelParams? params;
  final OwuiLlmModelMeta? meta;
  final OwuiAccessControl? accessControl;
  final bool? isActive;
  final int? updatedAt;
  final int? createdAt;

  OwuiLlmModelInfo({
    this.id,
    this.userId,
    this.baseModelId,
    this.name,
    this.params,
    this.meta,
    this.accessControl,
    this.isActive,
    this.updatedAt,
    this.createdAt,
  });

  factory OwuiLlmModelInfo.fromJson(Map<String, dynamic> json) {
    return OwuiLlmModelInfo(
      id: json['id'],
      userId: json['user_id'],
      baseModelId: json['base_model_id'],
      name: json['name'],
      params: json['params'] != null ? OwuiLlmModelParams.fromJson(json['params']) : null,
      meta: json['meta'] != null ? OwuiLlmModelMeta.fromJson(json['meta']) : null,
      accessControl: json['access_control'] != null ? OwuiAccessControl.fromJson(json['access_control']) : null,
      isActive: json['is_active'],
      updatedAt: json['updated_at'],
      createdAt: json['created_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (baseModelId != null) 'base_model_id': baseModelId,
      if (name != null) 'name': name,
      if (params != null) 'params': params!.toJson(),
      if (meta != null) 'meta': meta!.toJson(),
      if (accessControl != null) 'access_control': accessControl!.toJson(),
      if (isActive != null) 'is_active': isActive,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (createdAt != null) 'created_at': createdAt,
    };
  }
}

class OwuiLlmModelParams {
  final String? system;

  OwuiLlmModelParams({this.system});

  factory OwuiLlmModelParams.fromJson(Map<String, dynamic> json) {
    return OwuiLlmModelParams(
      system: json['system'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (system != null) 'system': system,
    };
  }
}

class OwuiLlmModelMeta {
  final String? profileImageUrl;
  final String? description;
  final Map<String, bool>? capabilities;
  final dynamic suggestionPrompts;
  final List<dynamic>? tags;
  final List<String>? toolIds;

  OwuiLlmModelMeta({
    this.profileImageUrl,
    this.description,
    this.capabilities,
    this.suggestionPrompts,
    this.tags,
    this.toolIds,
  });

  factory OwuiLlmModelMeta.fromJson(Map<String, dynamic> json) {
    return OwuiLlmModelMeta(
      profileImageUrl: json['profile_image_url'],
      description: json['description'],
      capabilities: json['capabilities']?.cast<String, bool>(),
      suggestionPrompts: json['suggestion_prompts'],
      tags: json['tags'],
      toolIds: List<String>.from(json['toolIds'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (profileImageUrl != null) 'profile_image_url': profileImageUrl,
      if (description != null) 'description': description,
      if (capabilities != null) 'capabilities': capabilities,
      if (suggestionPrompts != null) 'suggestion_prompts': suggestionPrompts,
      if (tags != null) 'tags': tags,
      if (toolIds != null) 'toolIds': toolIds,
    };
  }
}

class OwuiLlmModelList {
  final List<OwuiLlmModel> models;

  OwuiLlmModelList({required this.models});

  factory OwuiLlmModelList.fromJson(Map<String, dynamic> json) {
    return OwuiLlmModelList(
      models: (json['data'] as List).map((model) => OwuiLlmModel.fromJson(model)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'data': models.map((model) => model.toJson()).toList(),
    };
  }
}

class OwuiAccessControl {
  final OwuiAccessControlDetails? read;
  final OwuiAccessControlDetails? write;

  OwuiAccessControl({this.read, this.write});

  factory OwuiAccessControl.fromJson(Map<String, dynamic> json) {
    return OwuiAccessControl(
      read: json['read'] != null ? OwuiAccessControlDetails.fromJson(json['read']) : null,
      write: json['write'] != null ? OwuiAccessControlDetails.fromJson(json['write']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (read != null) 'read': read!.toJson(),
      if (write != null) 'write': write!.toJson(),
    };
  }
}

class OwuiAccessControlDetails {
  final List<String>? groupIds;
  final List<String>? userIds;

  OwuiAccessControlDetails({this.groupIds, this.userIds});

  factory OwuiAccessControlDetails.fromJson(Map<String, dynamic> json) {
    return OwuiAccessControlDetails(
      groupIds: List<String>.from(json['group_ids'] ?? []),
      userIds: List<String>.from(json['user_ids'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (groupIds != null) 'group_ids': groupIds,
      if (userIds != null) 'user_ids': userIds,
    };
  }
}

class OwuiStatusHistoryEntry {
  final String status;
  final String description;
  final bool done;

  OwuiStatusHistoryEntry({
    required this.status,
    required this.description,
    required this.done,
  });

  factory OwuiStatusHistoryEntry.fromJson(Map<String, dynamic> json) {
    return OwuiStatusHistoryEntry(
      status: json['status'],
      description: json['description'],
      done: json['done'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'description': description,
      'done': done,
    };
  }
}

/// Internal open-webui json encoder / decoder
/// Settings model for encoding/decoding settings data.
class OwuiSettings {
  final OwuiUiSettings ui;

  OwuiSettings({
    required this.ui,
  });

  factory OwuiSettings.fromJson(Map<String, dynamic> json) {
    return OwuiSettings(
      ui: OwuiUiSettings.fromJson(json['ui']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ui': ui.toJson(),
    };
  }
}

class OwuiUiSettings {
  final List<String> models;
  final bool memory;
  final Map<String, int> options;
  final OwuiTitleSettings title;
  final String version;
  final OwuiNotificationsSettings notifications;

  OwuiUiSettings({
    required this.models,
    required this.memory,
    required this.options,
    required this.title,
    required this.version,
    required this.notifications,
  });

  factory OwuiUiSettings.fromJson(Map<String, dynamic> json) {
    return OwuiUiSettings(
      models: List<String>.from(json['models']),
      memory: json['memory'],
      options: Map<String, int>.from(json['options']),
      title: OwuiTitleSettings.fromJson(json['title']),
      version: json['version'],
      notifications: OwuiNotificationsSettings.fromJson(json['notifications']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'models': models,
      'memory': memory,
      'options': options,
      'title': title.toJson(),
      'version': version,
      'notifications': notifications.toJson(),
    };
  }
}

class OwuiTitleSettings {
  final String model;
  final String modelExternal;
  final String prompt;

  OwuiTitleSettings({
    required this.model,
    required this.modelExternal,
    required this.prompt,
  });

  factory OwuiTitleSettings.fromJson(Map<String, dynamic> json) {
    return OwuiTitleSettings(
      model: json['model'],
      modelExternal: json['modelExternal'],
      prompt: json['prompt'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'model': model,
      'modelExternal': modelExternal,
      'prompt': prompt,
    };
  }
}

class OwuiNotificationsSettings {
  final String webhookUrl;

  OwuiNotificationsSettings({
    required this.webhookUrl,
  });

  factory OwuiNotificationsSettings.fromJson(Map<String, dynamic> json) {
    return OwuiNotificationsSettings(
      webhookUrl: json['webhook_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'webhook_url': webhookUrl,
    };
  }
}

