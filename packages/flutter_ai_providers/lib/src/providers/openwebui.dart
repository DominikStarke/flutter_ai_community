import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:http/http.dart' as http;
import 'dart:io' show WebSocket;

import 'package:uuid/v4.dart';
import 'package:collection/collection.dart'; // Add this import for firstWhereOrNull
import 'models/openwebui.dart';
 import 'package:http_parser/http_parser.dart';


export 'models/openwebui.dart';
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
    String baseUrl = 'http://localhost:3000/api',
    String? apiKey,
  }): _host = baseUrl,
      _apiKey = apiKey
  { _run(); }

  void _run () async {
    await _configure();
    await _startSocket();
    await _loadChatList();
    notifyListeners();
  }

  OwuiLlmModelList? _models;
  OwuiLlmModelList? _modelSelection;

  List<String> get models => List.from(_models?.models.map((model) => model.name) ?? []);
  List<String> get modelSelection {
    final settingsModels = _settings?.ui.models;

    if(_modelSelection == null && models.isNotEmpty) {
      return settingsModels ?? [models.first];
    } else if(_modelSelection == null && models.isEmpty) {
      return [];
    } else {
      return _modelSelection!.models.map((model) => model.name).toList();
    }
  }

  set modelSelection (List<String> models) {
    _modelSelection = OwuiLlmModelList(
      models: _models?.models.where((model) => models.contains(model.name)).toList() ?? []
    );
  }
  
  OwuiChatList? _chats;
  List<OwuiChatListEntry> get chats => List.from(_chats?.chats ?? []);

  ValueNotifier<List<OwuiChatListEntry>> chatListNotifier = ValueNotifier([]);
  ValueNotifier<List<OwuiLlmModel>> modelListChanged = ValueNotifier([]);

  final String _host;
  final String? _apiKey;
  String _sessionId = "";
  final List<OwuiImageAttachment> _imageAttachments = [];
  StreamController<String>? _responseStream;

  OwuiChat? _chat;
  OwuiSettings? _settings;
  WebSocket? _socket;

  final bool __debug = true;

  void __debugLog (String message, {String tag = "INFO"}) {
    if(!__debug) return;
    dev.log("OPENWEBUI[$tag] $message");
  }

  void __jsonLog (dynamic val, {String tag = "INFO"}) {
    if(!__debug) return;
    try {
      dev.log("OPENWEBUI[$tag] ${JsonEncoder.withIndent('  ').convert(val)}");
    } catch( e ) {
      __debugLog("$val", tag: "JSON DECODE ERROR");
    }
  }

  Future<void> _startSocket () async {
    

    final baseUri = Uri.parse(_host);
    final wsUrl = Uri.parse('ws://${baseUri.host}:${baseUri.port}/ws/socket.io/?EIO=4&transport=websocket');

    _socket = await WebSocket.connect(wsUrl.toString(), headers: {
      if (_apiKey != null) "Authorization": 'Bearer $_apiKey',
    });
    
    _socket?.listen(_handleSocketEvent,
      onDone: () {
        // TODO: Handle socket closed
        __debugLog("OPENWEBUI: SOCKET CLOSED");
      }, onError: (error) {
        // TODO: Handle socket errors
        __debugLog("OPENWEBUI: SOCKET ERROR: $error");
      }
    );
  }

  _handleSocketEvent(dynamic event) {
    final status = RegExp(r'^\d{1,2}').stringMatch(event);

    if (status  == null) {
      return;
    }

    final eventData = event.substring(status.length);
    switch (int.parse(status)) {
      case 0:
        _handleConnectEvent();
      case 2:
        _handlePingEvent();
        break;
      case 40:
        _handleSessionEvent(eventData);
        break;
      case 42: // nice
        final socketEvent = json.decode(eventData);
        
        if(socketEvent[0] == "chat-events") {
          final chatEvent = socketEvent[1];
          final chatEventData = chatEvent["data"];
          if(chatEventData["type"] == "chat:completion") {
            _handleCompletionEvent(chatEventData);
          } else if(chatEventData["type"] == "chat:title") {
            _handleTitleEvent(chatEvent);
          }  else if(chatEventData["type"] == "chat:tags") {
            _handleTagsEvent(chatEvent);
          } else if(chatEventData["type"] == "status") {
            _handleStatusEvent(chatEvent);
          }  else if(chatEventData["type"] == "citation") {
            _handleCitationEvent(chatEvent);
          }
        }
        break;
      default:
        __debugLog("UNHANDLED SOCKET EVENT: $event");
        break;
    }
  }

  /// Register callbacks for this chat.
  void _registerSocket () {
    __debugLog("${_chat?.id}", tag: "REQUEST CHAT USAGE");
    _socket?.add("43${json.encode(["usage", {
      "action": "chat",
      "model": modelSelection.first,
      "chat_id": _chat?.id,
    }])}");
  }

  void _handleConnectEvent () {
    __debugLog("SOCKET CONNECTED");
    _socket?.add('40{"token":"$_apiKey"}'); // Authorize
  }

  void _handlePingEvent() {
    __debugLog("PING");
    _socket?.add('3');
  }

  void _handleSessionEvent (String eventData) {
    final jsonData = json.decode(eventData);
    if(jsonData['sid'] != null) {
      __jsonLog(jsonData, tag: "SESSION");
      _sessionId = jsonData['sid'];
    }
  }

  void _handleCompletionEvent (Map<String, dynamic> chatEventData) {
    final completionEvent = OwuiChatCompletionEvent.fromJson(chatEventData["data"]);

    if(completionEvent.sources?.isNotEmpty ==  true) {
      __jsonLog(chatEventData["data"], tag: "CHAT ADD SOURCES");
    }

    final chunk = completionEvent.choices?.map((choice) => choice.content ?? '').join();
    if(chunk?.isNotEmpty == true) {
      __debugLog(chunk!, tag: "CHAT ADD CHUNK");
      _responseStream?.add(chunk);
    }

    if(completionEvent.done) {
      _responseStream?.close();
      _responseStream = null;
    }
  }

  void _handleTitleEvent (Map<String, dynamic> chatEvent) {
    if(chatEvent["chat_id"] == _chat?.id) {
      _chat?.title = chatEvent["data"]?["data"];
      __debugLog(_chat?.title ?? "", tag: "CHAT TITLE CHANGED");
      _loadChatList();
    }
  }

  void _handleTagsEvent (Map<String, dynamic> chatEvent) {
    if(chatEvent["chat_id"] == _chat?.id) {
      final tags = chatEvent["data"]?["data"];
      __jsonLog(tags, tag: "CHAT TAGS CHANGED");
      notifyListeners();
    }
  }

  void _handleStatusEvent (Map<String, dynamic> chatEvent) {
    final messageStatus = chatEvent["data"]?["type"] as String?;
    final messageStatusData = chatEvent["data"]?["data"];
    final messageId = chatEvent["data"]?["message_id"] as String?;
    final status = OwuiStatusHistoryEntry.fromJson(messageStatusData ?? {});

    // TODO: Handle status changes
    __jsonLog(messageStatusData ?? {}, tag: "CHAT STATUS CHANGED");
  }

  void _handleCitationEvent (Map<String, dynamic> chatEvent) {
    final messageStatus = chatEvent["data"]?["type"] as String?;
    final messageStatusData = chatEvent["data"]?["data"];
    final messageId = chatEvent["data"]?["message_id"] as String?;
    final citation = OwuiCitationData.fromJson(messageStatusData ?? {});

    // TODO: Handle citation changes
    __jsonLog(messageStatusData ?? {}, tag: "CHAT CITATIONS CHANGED");
  }

  Stream<String> _generateStream () async* {
    _responseStream = StreamController<String>.broadcast();
    final llmMessage = _chat?.tail;
    final reqMessages = _chat?.messages.where((m) => (m.text ?? "").isNotEmpty).toList() ?? [];
    final body = OwuiCompletionRequest(
      model: llmMessage?.model ?? "",
      toolIds: [
        'web_search'
      ],
      chatId: _chat?.id,
      messages: reqMessages,
      id: llmMessage?.id,
      sessionId: _sessionId,
      backgroundTasks: {
        if (reqMessages.length == 1) 'tags_generation': true,
        if (reqMessages.length == 1) 'title_generation': true,
      },
    ).toJson();

    __jsonLog(body, tag: "COMPLETION REQUEST");

    final httpRequest = http.Request('POST', Uri.parse("$_host/chat/completions"))
      ..headers.addAll({
        if(_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode(body);

    http.Client().send(httpRequest) // Cannot await this, otherwise we'll miss the first chunk of the response on the socket...
      .then((response) async {
        final jsonResponse = json.decode(await response.stream.bytesToString());
        __jsonLog(jsonResponse, tag: "COMPLETION RESPONSE");
      });

    await for (final message in _responseStream?.stream ?? Stream.empty()) {
      _chat?.history[_chat?.historyCurrentId]?.append(message);
      yield message;
    }
  }

  Future<OwuiFileAttachment> _handleAttachment (Attachment attachment) async {
    if(attachment is ImageFileAttachment) {
      _imageAttachments.clear(); // Only one image can be attached at a time? At least with llama3.2-vision + ollama.
      _imageAttachments.add(OwuiImageAttachment.fromImageAttachment(attachment));
      throw Exception('Image attachments are not supported yet.');
    } else if(attachment is FileAttachment) {

      final uri = Uri.parse('$_host/v1/files/'); // Replace with your OpenWebUI endpoint
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll({
          if(_apiKey != null) 'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'multipart/form-data',
          'Accept': 'application/json',
        })
        ..files.add(http.MultipartFile.fromBytes('file', attachment.bytes, filename: attachment.name, contentType: MediaType.parse(attachment.mimeType)));

      final response = await request.send();
      
      if (response.statusCode == 200) {
        final responseBody = json.decode(await response.stream.bytesToString());
        __jsonLog(responseBody, tag: "FILE UPLOAD RESPONSE");
        return OwuiFileAttachment.fromJson(responseBody);
      } else {
        throw Exception('Failed to upload file: ${response.reasonPhrase}');
      }
    }
    throw Exception('Unsupported FileAttachment type: $attachment');
  }

  Future<void> _loadChatList () async {
    final response = await http.get(
      Uri.parse('$_host/v1/chats/list'),
      headers: {
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final responseBody = json.decode(response.body);
      __jsonLog(responseBody, tag: "LOAD CHAT LIST RESPONSE");
      final chatList = OwuiChatList.fromJson(responseBody);
      // Sort the chat list by the newest
      chatList.chats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      chatListNotifier.value = chatList.chats;
      _chats = chatList;
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
      final responseBody = json.decode(response.body);
      __debugLog(responseBody, tag: "LIST CHAT PAGE $page");
      return OwuiChatList.fromJson(responseBody).chats;
    } else {
      throw Exception('Failed to poll name: ${response.reasonPhrase}');
    }
  }

  Future<OwuiChat> _saveChat () async {
    final body = _chat?.toJson(models: modelSelection) ?? {};
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
      final jsonResponse = json.decode(response.body);
      __jsonLog(jsonResponse, tag: "SAVE CHAT RESPONSE");
      _chat = OwuiChat.fromJson(jsonResponse); // Avoid side effect?
      return _chat!;
    } else {
      throw Exception('Failed to save chat: ${response.reasonPhrase}');
    }
  }

  Future<void> _completeMessage() async {
    final llmMessage = _chat?.history[_chat?.historyCurrentId];
    llmMessage?.done = true;

    final body = {
      'model': llmMessage?.model ?? "",
      'messages': _chat?.messages.map((message) => message.toCompletedJson()).toList(),
      'chat_id': _chat?.id,
      'session_id': _sessionId,
      'id': llmMessage?.id,
    };

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

  Future<void> _configure () async {
    if(_settings == null) {
      await _loadSettings();
    }

    if(_models == null) {
      await _loadModels();
    }
  }

  Future<void> _loadSettings() async {
    final response = await http.get(
      Uri.parse('$_host/v1/users/user/settings'),
      headers: {
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(response.body);
      _settings = OwuiSettings.fromJson(jsonResponse);
      __jsonLog(jsonResponse, tag: "SETTINGS");
      
    } else {
      throw Exception('Failed to load settings: ${response.reasonPhrase}');
    }
  }

  Future<void> _loadModels() async {
    final response = await http.get(
      Uri.parse('$_host/models'),
      headers: {
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(response.body);
      __jsonLog(jsonResponse, tag: "MODELS");
      _models = OwuiLlmModelList.fromJson(jsonResponse);
    } else {
      throw Exception('Failed to load models: ${response.reasonPhrase}');
    }
  }

  /// ******
  /// PUBLIC 
  /// ******


  @override
  Stream<String> generateStream(
    String prompt, {
    Iterable<Attachment> attachments = const [],
  }) async* {
    final userMessage = OwuiChatMessage.user(prompt,
      attachments: attachments,
      models: modelSelection
    );

    for(final model in modelSelection) {
      final llmMessage = OwuiChatMessage.llm(
        parentId: userMessage.id,
        model: model,
        modelIdx: modelSelection.indexOf(model),
        modelName: model
      );
      userMessage.childrenIds.add(llmMessage.id);
      // TODO: Make multi chats actually work
      yield* _generateStream();
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
        models: modelSelection
      );
      await createChat([userMessage]);
      await _saveChat();

      notifyListeners();

      yield* _generateStream();
    } else {
      List<OwuiFileAttachment> files = [];
      for(final attachment in attachments) {
       files.add(await _handleAttachment(attachment));
      }

      _chat?.appendMessage(OwuiChatMessage.user(prompt,
        attachments: attachments,
        models: modelSelection,
        files: files,
        parentId: _chat?.tail?.id
      ));

      for (final model in modelSelection) {
        _chat?.appendMessage(OwuiChatMessage.llm(
          parentId: _chat?.tail?.id,
          model: model,
          modelIdx: modelSelection.indexOf(model),
          modelName: model
        ));
        
        notifyListeners();
        
        yield* _generateStream();
      }
    }

    await _completeMessage();

    await _saveChat();
  }

  Future<void> createChat (Iterable<ChatMessage> messages) async {
    await _configure();

    final List<Future> owuiFileUploads = [];

    _chat = OwuiChat(
      models: modelSelection,
    );

    for(final message in messages) {
      final List<OwuiFileAttachment> owuiMessageFiles = [];
      if(message.attachments.isNotEmpty) {
        for (final attachment in message.attachments) {
          owuiFileUploads.add(Future(() async {
            final owuiAttachment = await _handleAttachment(attachment);
            owuiMessageFiles.add(owuiAttachment);
            _chat?.historyFiles.add(owuiAttachment);

          }));
        }
      }

      _chat?.appendMessage(OwuiChatMessage(
        origin: message.origin,
        text: message.text,
        timestamp: DateTime.now(),
        attachments: message.attachments,
        files: owuiMessageFiles,
        models: modelSelection,
        model: message.origin == MessageOrigin.user ? null : modelSelection.first,
        modelIdx: message.origin == MessageOrigin.user ? null :  0,
        modelName: message.origin == MessageOrigin.user ? null :  modelSelection.first,
      ));
    }

    notifyListeners();

    if (owuiFileUploads.isNotEmpty) {
      await Future.wait(owuiFileUploads);
      notifyListeners();
    }

    final response = await http.post(
      Uri.parse('$_host/v1/chats/new'),
      headers: {
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(_chat?.toJson()),
    );

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(response.body);
      __jsonLog(jsonResponse, tag: "CREATE CHAT RESPONSE");
      final chat = OwuiChat.fromJson(jsonResponse, models: modelSelection); //, extraFiles: owuiFiles, extraHistory: _chat?.history ?? {});
      _chat = chat;

      // Register callbacks for this chat.
      _socket?.add("43${json.encode(["usage", {
        "action": "chat",
        "model": modelSelection.first,
        "chat_id": chat.id,
      }])}");
      
      chat.appendMessage(OwuiChatMessage.llm(
        parentId: chat.tail?.id,
        model: modelSelection.first,
        modelIdx: 0,
        modelName: modelSelection.first
      ));
    } else {
      throw Exception('Failed to create chat: ${response.reasonPhrase}');
    }
  }

  Future<OwuiChat> loadChat (String chatId) async {
    await _configure();
    final response = await http.get(
      Uri.parse('$_host/v1/chats/$chatId'),
      headers: {
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(response.body);
      __jsonLog(jsonResponse, tag: "LOAD CHAT RESPONSE");
      _chat = OwuiChat.fromJson(jsonResponse);
      _registerSocket();
      notifyListeners();
      return _chat!;
    } else {
      throw Exception('Failed to select chat: ${response.reasonPhrase}');
    }
  }

  Future<void> deleteChat (String chatId) async {
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
        notifyListeners();
      }
    } else {
      throw Exception('Failed to delete chat: ${response.reasonPhrase}');
    }
  }

  void clearChat () {
    _chat = null;
    notifyListeners();
  }



  @override
  Iterable<OwuiChatMessage> get history => _chat?.messages ?? []; // List.from(_chat?.messages ?? []);

  @override
  set history(Iterable<ChatMessage> newHistory) {
    // ARGH
    final currentBranch = _chat?.messages;
    final branchFromChild = currentBranch?.toList()[history.length - 2];
    final branchOnParent = _chat?.history[branchFromChild?.parentId];

    throw("Setting history is not supported for OpenWebUIProvider. Use [loadChat] and [createChat] instead.");
  }
}
