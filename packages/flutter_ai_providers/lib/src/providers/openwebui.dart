import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:http/http.dart' as http;
import 'dart:io' show WebSocket;

import 'package:uuid/v4.dart';
import 'package:collection/collection.dart'; // Add this import for firstWhereOrNull

/// Internal open-webui json encoder / decoder
/// Encode a request to the open-webui API.
class _OwuiChatRequest {
  final String model;
  final String? chatId;
  final String? sessionId;
  final String? id;
  final List<OwuiChatMessage> messages;
  final List<_OwuiFileAttachment>? files;
  final List<_OwuiImageAttachment>? images;
  final Map<String, bool> backgroundTasks;

  /// Creates an instance of [_OwuiChatRequest].
  ///
  /// [model] is the model to be used for the chat.
  /// [messages] is the list of messages in the chat history.
  /// [files] files to be attached to the next request.
  /// [images] images to be attached to the next request.
  _OwuiChatRequest({
    required this.model,
    required this.messages,
    this.id,
    this.chatId,
    this.files,
    this.images,
    this.sessionId,
    this.backgroundTasks = const {},
  });

  /// Converts the [_OwuiChatRequest] instance to a JSON object.
  Map<String, dynamic> toJson() => {
    'model': model,
    'stream': true,
    'chat_id': chatId,
    'id': id,
    'messages': messages.map((message) => message.toCompletionJson()).toList(),
    // 'features': {
    //   'web_search': true,
    // },
    'session_id': sessionId,
    'background_tasks': backgroundTasks,
    'tool_ids': ['web_search'],
    'files': files?.map((file) => file.toJson()).toList(),
  };

  String toJsonString() => jsonEncode(toJson());
}

/// Internal open-webui json encoder / decoder
/// Decode a chat response from the open-webui API.
class _OwuiChatResponse {
  final List<_OwuiChatResponseChoice> choices;
  final bool done;

  /// Creates an instance of [_OwuiChatResponse].
  ///
  /// [choices] is the list of choices in the response.
  _OwuiChatResponse({required this.choices, required this.done});

  /// Creates an instance of [_OwuiChatResponse] from a JSON object.
  factory _OwuiChatResponse.fromJson(Map<String, dynamic> json) {
    return _OwuiChatResponse(
      done: json['done'] ?? false,
      choices: (json['choices'] as List?)?.map((choice) => _OwuiChatResponseChoice.fromJson(choice)).toList() ?? [],
    );
  }
}

/// Internal open-webui json encoder / decoder
/// Decoder for the choice part of [_OwuiChatResponse].
class _OwuiChatResponseChoice {
  final String? content;
  final int? index;
  final dynamic longprobs; // whats type is this?
  final dynamic finishRead; // what type is this?
  

  /// Creates an instance of [_OwuiChatResponseChoice].
  ///
  /// [message] is the message in the choice.
  _OwuiChatResponseChoice({
    this.content,
    this.index,
    this.longprobs,
    this.finishRead,
  });

  /// Creates an instance of [_OwuiChatResponseChoice] from a JSON object.
  factory _OwuiChatResponseChoice.fromJson(Map<String, dynamic> json) {
    return _OwuiChatResponseChoice(
      content: json['delta']?['content'],
      index: json['index'],
      longprobs: json['longprobs'],
      finishRead: json['finishRead'],
    );
  }
}

/// Internal open-webui json encoder / decoder
class _OwuiImageAttachment {
  final String type;
  final Map<String, String> imageUrl;
  final String name;

  _OwuiImageAttachment({
    required this.type,
    required this.imageUrl,
    required this.name,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'image_url': imageUrl,
    'name': name,
  };

  factory _OwuiImageAttachment.fromImageAttachment(ImageFileAttachment attachment) {
    final base64Image = base64Encode(attachment.bytes);
    return _OwuiImageAttachment(
      type: 'image_url',
      imageUrl: {'url': "data:${attachment.mimeType};base64,$base64Image"},
      name: attachment.name,
    );
  }
}

/// Internal open-webui json encoder / decoder
class _OwuiFileAttachment {
  final String type;
  final String id;

  _OwuiFileAttachment({
    required this.type,
    required this.id,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'id': id,
  };
}

class _OwuiChatList {
  final List<OwuiChatListEntry> chats;

  _OwuiChatList({required this.chats});

  factory _OwuiChatList.fromJson(List<dynamic> json) {
    return _OwuiChatList(
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
  // final List<OwuiChatMessage> messages;
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
    this.history = const {},
    required this.historyCurrentId,
    this.models,
  }) : 
    createdAt = createdAt ?? DateTime.now(),
    updatedAt = updatedAt ?? DateTime.now();

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
      historyCurrentId: json['chat']?['history']?['currentId'],
      models: models ?? (json['models'] is List<String> ? json['models'].cast<String>() : []),
      history: {
        if(json['chat']?['history']?['messages'] is Map<String, dynamic>)
          for(final entry in json['chat']['history']['messages'].entries)
            entry.key: OwuiChatMessage.fromJson(entry.value)
      }
    );
  }

  List<OwuiChatMessage> get messages {
    List<OwuiChatMessage> orderedMessages = [];
    OwuiChatMessage? currentMessage = history[historyCurrentId];

    while (currentMessage != null) {
      orderedMessages.add(currentMessage);
      currentMessage = history.values.firstWhereOrNull((message) => message.id == currentMessage?.parentId);
    }

    return orderedMessages.reversed.toList();
  }

  Map<String, dynamic> toJson({List<String>? models}) {
    return {
      'chat' : {
        'params': {},
        'models': models ?? this.models ?? [],
        'files': [],
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
  final MessageOrigin role;
  final DateTime timestamp;
  final List<String>? models;
  final String? model;
  final int? modelIdx;
  final String? modelName;
  bool? done;

  OwuiChatMessage({
    String? id,
    this.parentId,
    this.childrenIds = const [],
    required this.role,
    String? content,
    required this.timestamp,
    this.models,
    this.model,
    this.modelIdx,
    this.modelName,
    this.done
  }):
    id = id ?? UuidV4().generate(),
    super(
      origin: role,
      text: content,
      attachments: []
    );

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
      role: MessageOrigin.llm,
      content: null,
      timestamp: DateTime.now(),
      models: null,
      model: model,
      modelIdx: modelIdx,
      modelName: modelName,
      done: done,
    );
  }

  factory OwuiChatMessage.user(String content, {
    required Iterable<Attachment> attachments,
    List<String>? models,
    String? parentId
  }) {
    return OwuiChatMessage(
      parentId: parentId,
      childrenIds: [],
      role: MessageOrigin.user,
      content: content,
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
        role: MessageOrigin.user,
        content: null,
        timestamp: DateTime.now(),
        models: null,
      );
    }
    return OwuiChatMessage(
      id: json['id'],
      parentId: json['parentId'],
      childrenIds: List<String>.from(json['childrenIds'] ?? []),
      role: json['role'] == 'user' ? MessageOrigin.user : MessageOrigin.llm,
      content: json['content'] == null || json['content'] == '' ? null : utf8.decode((json['content']).runes.toList()),
      timestamp: DateTime.fromMillisecondsSinceEpoch((json['timestamp'] ?? 0) * 1000),
      models: List<String>.from(json['models'] ?? []),
      done: json['done'],
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
      'role': role == MessageOrigin.user ? 'user' : 'assistant',
      'content': text,
      'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
      if(model != null) 'model': model,
      if(models != null) 'models': models,
      if(modelIdx != null) 'modelIdx': modelIdx,
      if(modelName != null) 'modelName': modelName,
      if(role == MessageOrigin.llm) 'userContext': null,
      if(role == MessageOrigin.llm && done == true) 'done': done,
    };
  }

  Map<String, dynamic> toCompletionJson() {
    return {
      'role': role == MessageOrigin.user ? 'user' : 'assistant',
      'content': text,
    };
  }
}

/// A provider for [open-webui](https://openwebui.com/)
/// Use open-webui as unified chat provider.
class OpenWebUIProvider extends LlmProvider with ChangeNotifier {
  /// Creates an [OpenWebUIProvider] instance with an optional chat history.
  ///
  /// The [history] parameter is an optional iterable of [ChatMessage] objects
  /// representing the chat history
  /// The [model] parameter is the ai model to be used for the chat.
  /// The [baseUrl] parameter is the host of the open-webui server.
  /// For example port 3000 on localhost use 'http://localhost:3000'
  /// The [apiKey] parameter is the API key for the open-webui server.
  /// See the [docs](https://docs.openwebui.com/) for more information.
  /// Example:
  /// ``` dart
  /// LlmChatView(
  ///   provider: OpenwebuiProvider(
  ///     host: 'http://127.0.0.1:3000',
  ///     model: 'llama3.1:latest',
  ///     apiKey: "YOUR_API_KEY",
  ///     history: [],
  ///   ),
  /// )
  /// ```
  OpenWebUIProvider({
    // Iterable<ChatMessage>? history,
    required String model,
    String baseUrl = 'http://localhost:3000/api',
    String? apiKey,
  }): _model = model,
      _host = baseUrl,
      _apiKey = apiKey
  {
    _startSocket();
  }
  
  final String _model;
  final String _host;
  final String? _apiKey;
  String _sessionId = "";
  final List<_OwuiFileAttachment> _fileAttachments = [];
  final List<_OwuiImageAttachment> _imageAttachments = [];
  StreamController<String>? _responseStream;

  OwuiChat? _chat;
  WebSocket? _socket;

  void __debugPrint (String message) {
    print(message);
  }

  @override
  Stream<String> generateStream(
    String prompt, {
    Iterable<Attachment> attachments = const [],
  }) async* {
    final userMessage = OwuiChatMessage.user(prompt,
      attachments: attachments,
      models: [_model]
    );

    final llmMessage = OwuiChatMessage.llm(
      parentId: userMessage.id,
      model: _model,
      modelIdx: 0,
      modelName: _model
    );
    userMessage.childrenIds.add(llmMessage.id);
    
    yield* _generateStream(llmMessage);
  }

  Future<void> _startSocket () async {
    final baseUri = Uri.parse(_host);
    final wsUrl = Uri.parse('ws://${baseUri.host}:${baseUri.port}/ws/socket.io/?EIO=4&transport=websocket');

    _socket = await WebSocket.connect(wsUrl.toString(), headers: {
      if (_apiKey != null) "Authorization": 'Bearer $_apiKey',
    });
    
    _socket?.listen((event) {
      final status = RegExp(r'^\d{1,2}').stringMatch(event);
      if (status != null) {
        _handleSocketEvent(int.parse(status), event.substring(status.length));
      }
    }, onDone: () {
      __debugPrint("SOCKET CLOSED");
    }, onError: (error) {
      __debugPrint("SOCKET ERROR: $error");
    });
  }

  _handleSocketEvent(int status, String eventData) {
    switch (status) {
      case 0:
        __debugPrint("SOCKET CONNECTED");
        _socket?.add('40{"token":"$_apiKey"}'); // Authorize
      case 2:
        __debugPrint("SOCKET PING");
        _socket?.add('3');
        break;
      case 40:
        __debugPrint("SOCKET ON CONNECT");
        final jsonData = json.decode(eventData);
        if(jsonData['sid'] != null) {
          _sessionId = jsonData['sid'];
        }
        break;
      case 42:
        __debugPrint("SOCKET MESSAGE EVENT");
        final jsonEvent = json.decode(eventData);
        if(jsonEvent[0] == "chat-events") {
          final jsonMessage = jsonEvent[1];
          final data = jsonMessage["data"];

          if(data["type"] == "chat:completion") {
            final response = _OwuiChatResponse.fromJson(data["data"]);
            if(response.done) {
              _responseStream?.close();
              _responseStream = null;
            }
            final chunk = response.choices.map((choice) => choice.content ?? '').join();
            if(chunk.isNotEmpty) {
              __debugPrint("ADDING TO STREAM ${chunk}");
              _responseStream?.add(chunk);
            }
          } else if(data["type"] == "chat:title") {
            if(jsonMessage["chat_id"] == _chat?.id) {
              _chat?.title = data["data"];
              __debugPrint("CHAT TITLE CHANGED: ${_chat?.title}");
              notifyListeners();
            }
          }  else if(data["type"] == "chat:tags") {
            if(jsonMessage["chat_id"] == _chat?.id) {
              final tags = data["data"]?.cast<String>();
              __debugPrint("CHAT TAGS CHANGED: $tags");
              notifyListeners();
            }
          }
        }
        break;
      default:
        break;
        // __debugPrint("SOCKET EVENT: $event");
    }
  }

  @override
  Stream<String> sendMessageStream(
    String prompt, {
    Iterable<Attachment> attachments = const [],
  }) async* {
    if(_chat == null) {
      final userMessage = OwuiChatMessage.user(prompt,
        attachments: attachments,
        models: [_model]
      );
      final llmMessage = await createChat([userMessage]);
      await _saveChat();
      notifyListeners();

      yield* _generateStream(llmMessage);
    } else {
      final userMessage = OwuiChatMessage.user(prompt,
        attachments: attachments,
        models: [_model],
        parentId: _chat?.history[_chat?.historyCurrentId]?.id
      );

      final llmMessage = OwuiChatMessage.llm(
        parentId: userMessage.id,
        model: _model,
        modelIdx: 0,
        modelName: _model
      );

      userMessage.childrenIds.add(llmMessage.id);
      
      _chat?.history.addAll({
        userMessage.id: userMessage,
        llmMessage.id: llmMessage,
      });
      _chat?.historyCurrentId = llmMessage.id;
      
      notifyListeners();
      
      yield* _generateStream(llmMessage);
    }

    await _completeMessage();

    await _saveChat();
  }

  Stream<String> _generateStream(OwuiChatMessage llmMessage) async* {
    _responseStream = StreamController<String>.broadcast();
    final files = history.lastWhere((m) => m.origin == MessageOrigin.user).attachments;
    // final llmMessage = history.last;
    if(files.isNotEmpty) {
      for (var file in files) {
        await _handleAttachment(file);
      }
    }

    final reqMessages = _chat?.messages.where((m) => m.isInitialized()).toList() ?? [];
    final body = _OwuiChatRequest(
      model: _model,
      chatId: _chat?.id,
      messages: reqMessages,
      files: _fileAttachments,
      images: _imageAttachments,
      id: llmMessage.id,
      sessionId: _sessionId,
      backgroundTasks: {
        if (reqMessages.length == 1) 'tags_generation': true,
        if (reqMessages.length == 1) 'title_generation': true,
      },
    ).toJson();

    __debugPrint("COMLETION REQUEST");
    __debugPrint(JsonEncoder.withIndent('  ').convert(body));
    __debugPrint("=================");

    final httpRequest = http.Request('POST', Uri.parse("$_host/chat/completions"))
      ..headers.addAll({
        if(_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode(body);

    http.Client().send(httpRequest); // Cannot await this, otherwise we'll miss the first chunk of the response on the socket...

    if(_responseStream != null) {
      await for (final message in _responseStream!.stream) {
        _chat?.history[_chat?.historyCurrentId]?.append(message);
        yield message;
      }
    }
  }

  Future<void> _handleAttachment(Attachment attachment) async {
    if(attachment is ImageFileAttachment) {
      _imageAttachments.clear(); // Only one image can be attached at a time? At least with llama3.2-vision + ollama.
      _imageAttachments.add(_OwuiImageAttachment.fromImageAttachment(attachment));
    } else if(attachment is FileAttachment) {
      final uri = Uri.parse('$_host/v1/files/'); // Replace with your OpenWebUI endpoint
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll({
          if(_apiKey != null) 'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'multipart/form-data',
          'Accept': 'application/json',
        })
        ..files.add(http.MultipartFile.fromBytes('file', attachment.bytes, filename: attachment.name));

      final response = await request.send();
      if (response.statusCode == 200) {
        final responseBody = await response.stream.bytesToString();
        final jsonResponse = json.decode(responseBody);
        _fileAttachments.add(_OwuiFileAttachment(
          type: 'file',
          id: jsonResponse['id'].toString(),
        ));
      } else {
        throw Exception('Failed to upload file: ${response.reasonPhrase}');
      }
    }
  }

  Future<List<OwuiChatListEntry>> listChats () async {
    final response = await http.get(
      Uri.parse('$_host/v1/chats/list'),
      headers: {
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final chatList = _OwuiChatList.fromJson(json.decode(response.body));
      // Sort the chat list by the newest
      chatList.chats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      return chatList.chats;
    } else {
      throw Exception('Failed to load chats: ${response.reasonPhrase}');
    }
  }

  Future<List<OwuiChatListEntry>> listChatsPage (int page) async {
    final response = await http.get(
      Uri.parse('$_host/v1/chats/?page=$page'),
      headers: {
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Accept': 'application/json',
      }
    );

    if(response.statusCode == 200) {
      return _OwuiChatList.fromJson(json.decode(response.body)).chats;
    } else {
      throw Exception('Failed to poll name: ${response.reasonPhrase}');
    }
  }

  Future<OwuiChat> loadChat (String chatId) async {
    final response = await http.get(
      Uri.parse('$_host/v1/chats/$chatId'),
      headers: {
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      _chat = OwuiChat.fromJson(json.decode(response.body));

      // Register callbacks for this chat.
      _socket?.add("43${json.encode(["usage", {
        "action": "chat",
        "model": _model,
        "chat_id": _chat?.id,
      }])}");

      __debugPrint(JsonEncoder.withIndent('  ').convert(json.decode(response.body)));
      notifyListeners();
      return _chat!;
    } else {
      throw Exception('Failed to select chat: ${response.reasonPhrase}');
    }
  }

  Future<OwuiChat> _saveChat () async {
    _chat?.historyCurrentId = history.last.id;

    final body = _chat?.toJson(models: [_model]) ?? {};
    __debugPrint("SAVE CHAT");

    __debugPrint(JsonEncoder.withIndent('  ').convert(body));
    __debugPrint("============");
    final response = await http.post(
      Uri.parse('$_host/v1/chats/${_chat?.id}'),
      headers: {
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      _chat = OwuiChat.fromJson(json.decode(response.body));
      return _chat!;
    } else {
      throw Exception('Failed to save chat: ${response.reasonPhrase}');
    }
  }

  Future<OwuiChatMessage> createChat (List<ChatMessage> messages) async {
    String? nextParentId;
    String nextMessageId = UuidV4().generate();
    final owuiMessages = messages.map((message) {
      final messageId = nextMessageId;
      nextMessageId = UuidV4().generate();

      final parentId = nextParentId;
      nextParentId = messageId;

      return OwuiChatMessage(
        role: message.origin,
        content: message.text,
        timestamp: DateTime.now(),
        childrenIds: [
          if(message != messages.last)
            nextMessageId
        ],
        parentId: parentId,
        id: messageId,
        models: [_model],
        model: message.origin == MessageOrigin.user ? null : _model,
        modelIdx: message.origin == MessageOrigin.user ? null :  0,
        modelName: message.origin == MessageOrigin.user ? null :  _model,
      );
    }).toList();
    
    final chat = OwuiChat(
      historyCurrentId: owuiMessages.last.id,
      models: [_model],
      id: "",
      history: {
        for(final message in owuiMessages)
          message.id: message
      },
      // messages: owuiMessages,
    ).toJson();

    __debugPrint("CREATE CHAT");
    __debugPrint(JsonEncoder.withIndent('  ').convert(chat));
    __debugPrint("===========");

    final response = await http.post(
      Uri.parse('$_host/v1/chats/new'),
      headers: {
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(chat),
    );

    if (response.statusCode == 200) {
      final chat = OwuiChat.fromJson(json.decode(response.body), models: [_model]);
      _chat = chat;

      // Register callbacks for this chat.
      _socket?.add("43${json.encode(["usage", {
        "action": "chat",
        "model": _model,
        "chat_id": chat.id,
      }])}");
      
      final userMessage = _chat?.history[_chat?.historyCurrentId];
      final llmMessage = OwuiChatMessage.llm(
        parentId: userMessage?.id,
        model: _model,
        modelIdx: 0,
        modelName: _model
      );
      userMessage?.childrenIds.add(llmMessage.id);
      chat.history.addAll({
        llmMessage.id : llmMessage,
      });
      chat.historyCurrentId = llmMessage.id;

      return llmMessage;
    } else {
      throw Exception('Failed to create chat: ${response.reasonPhrase}');
    }
  }

  Future<void> _completeMessage() async {
    final llmMessage = _chat?.history[_chat?.historyCurrentId];
    llmMessage?.done = true;

    final body = {
      'model': _model,
      'messages': _chat?.messages.map((message) => message.toJson()).toList(),
      'chat_id': _chat?.id,
      'session_id': _sessionId,
      'id': llmMessage?.id,
    };

    __debugPrint("COMPLETE MESSAGE");
    __debugPrint(JsonEncoder.withIndent('  ').convert(body));
    __debugPrint("================");
    
    final response = await http.post(
      Uri.parse('$_host/chat/completed'),
      headers: {
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      // history.last.done = true;
    } else {
      throw Exception('Failed to complete chat: ${response.reasonPhrase}');
    }
  }

  void clearChat () {
    _chat = null;
    notifyListeners();
  }

  Future<void> deleteChat(String chatId) async {
    final response = await http.delete(
      Uri.parse('$_host/v1/chats/$chatId'),
      headers: {
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      if(_chat?.id == chatId) {
        _chat = null;
      }
      notifyListeners();
    } else {
      throw Exception('Failed to delete chat: ${response.reasonPhrase}');
    }
  }



  @override
  Iterable<OwuiChatMessage> get history => _chat?.messages ?? []; // List.from(_chat?.messages ?? []);

  @override
  set history(Iterable<ChatMessage> history) {
    throw("Setting history is not supported for OpenWebUIProvider. Use [loadChat] and [createChat] instead.");
  }
}
