import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:http/http.dart' as http;
import 'dart:io' show WebSocket;

import 'models/openwebui.dart';
import 'package:http_parser/http_parser.dart';

export 'models/openwebui.dart';

const __debug = false;

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

/// A provider for [open-webui](https://openwebui.com/)
/// Use open-webui as unified chat provider.
class OpenWebUIProvider extends LlmProvider with ChangeNotifier {
  /// Creates an [OpenWebUIProvider] instance with an optional chat history.
  ///
  /// The [baseUrl] parameter is the host of the open-webui server.
  /// For example port 3000 on localhost use 'http://localhost:3000'
  /// The [apiKey] parameter is the API key for the open-webui server.
  /// See the [docs](https://docs.openwebui.com/) for more information.
  /// Example:
  /// ``` dart
  /// LlmChatView(
  ///   provider: OpenwebuiProvider(
  ///     host: 'http://127.0.0.1:3000',
  ///     apiKey: "YOUR_API_KEY",
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

  final String _host;
  final String? _apiKey;

  // Amount of messages that are not yet completed
  // Used to determine when to close the completion stream.
  int _incompleteMessages = 0;

  // Streams of this provider emits only empty messages.
  StreamController<String>? _responseStream;

  /// FIXME: Model handling is way too complex and buggy.
  OwuiLlmModelList? _models;
  
  /// FIXME: Model handling is way too complex and buggy.
  OwuiLlmModelList? _modelSelection;

  /// FIXME: Model handling is way too complex and buggy.
  List<String> get models => List.from(_models?.models.map((model) => model.id) ?? []);
  
  /// FIXME: Model handling is way too complex and buggy.
  List<String> get modelSelection {
    final settingsModels = _settings?.ui.models;
    final userSelectedModels = _modelSelection?.models.isEmpty ?? true;

    if(userSelectedModels && models.isNotEmpty) {
      final retval = settingsModels ?? [models.first];
      return retval;
    } else if(userSelectedModels && models.isEmpty) {
      return [];
    } else {
      return _modelSelection!.models.map((model) => model.id).toList();
    }
  }

  /// FIXME: Model handling is way too complex and buggy.
  set modelSelection (List<String> models) {
    _modelSelection = OwuiLlmModelList(
      models: _models?.models.where((model) => models.contains(model.id)).toList() ?? []
    );
    modelListNotifier.value = _modelSelection?.models ?? [];
  }

  /// Some weird utf-8 <> utf-16 conversion issue.
  /// Everything has to go through this function or we'll end up with infinitly big strings!
  dynamic jsonDecode (String value) {
    try {
      final runes = value.runes.toList();
      return json.decode(utf8.decode(runes));
    } catch (e) {
      return json.decode(value);
    }
  }

  
  /// A list of chats in the history. Filled once [_loadChat] is called.
  OwuiChatList? _chats;

  /// A list of chats in the history. Filled once [_loadChat] is called.
  List<OwuiChatListEntry> get chats => List.from(_chats?.chats ?? []);

  /// Emits a list of chat history entries, when the history changes.
  /// Typically called right after after [_loadChat] is called.
  ValueNotifier<List<OwuiChatListEntry>> chatListNotifier = ValueNotifier([]);

  /// Emits a list of Llm Models, when the list changes.
  /// Typically called right after after [_loadModels] is called.
  ValueNotifier<List<OwuiLlmModel>> modelListNotifier = ValueNotifier([]);



  /// Filled by the library when [_loadSettings] is called and subsequently a session_id is annotated on the socket.
  String _sessionId = "";
  final List<OwuiImageAttachment> _imageAttachments = [];
  
  /// Internal state representing the current chat.
  OwuiChat? _chat;

  /// Internal state representing the current settings, set by [_loadSettings].
  OwuiSettings? _settings;

  /// Openwebui socket connection.
  /// All spontaneous events are handled here, including chat completions.
  WebSocket? _socket;

  /// Openwebui socket connection.
  /// All spontaneous events are handled here, including chat completions.
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

  /// Handle the different types of socket events.
  /// Currently implemented:  
  /// * 42
  ///   - chat:completion
  ///   - chat:title
  ///   - chat:tags
  ///   - status
  ///   - citation
  /// * 40
  ///   - Session
  /// * 2
  ///   - Ping
  /// * 0:
  ///   - Connect
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
        final socketEvent = jsonDecode(eventData);
        
        if(socketEvent[0] == "chat-events") {
          final chatEvent = socketEvent[1];
          final chatEventData = chatEvent["data"];
          final messageId = chatEvent?["message_id"] ?? "";
          if(chatEventData["type"] == "chat:completion") {
            _handleCompletionEvent(messageId, chatEventData);
          } else if(chatEventData["type"] == "chat:title") {
            _handleTitleEvent(chatEvent);
          }  else if(chatEventData["type"] == "chat:tags") {
            _handleTagsEvent(chatEvent);
          } else if(chatEventData["type"] == "status") {
            _handleStatusEvent(messageId, chatEventData);
          }  else if(chatEventData["type"] == "citation") {
            _handleCitationEvent(messageId, chatEventData);
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

  /// The socket has connected and successfully received a 0 message.
  /// Authorize the socket with the API key.
  void _handleConnectEvent () {
    __debugLog("SOCKET CONNECTED");
    _socket?.add('40{"token":"$_apiKey"}'); // Authorize
  }

  /// Respond to ping from the server.
  /// The connection closes if the server does not receive a ping within x seconds.
  void _handlePingEvent() {
    __debugLog("PING");
    _socket?.add('3');
  }

  /// The server assigned a session id for us to store.
  /// This is required for chat completions.
  void _handleSessionEvent (String eventData) {
    final jsonData = jsonDecode(eventData);
    if(jsonData['sid'] != null) {
      __jsonLog(jsonData, tag: "SESSION");
      _sessionId = jsonData['sid'];
    }
  }

  /// Assign the response text, sources and completion status to the chat message.
  /// If the completion is done close the completion stream and call [_endCompletion].
  /// [messageId] reference to the message in [_chat.history].
  /// [chatEventData] the completion event data.
  void _handleCompletionEvent (String messageId, Map<String, dynamic> chatEventData) {
    final completionEvent = OwuiChatCompletionEvent.fromJson(chatEventData["data"]);

    if(completionEvent.sources?.isNotEmpty ==  true) {
      _chat?.history[messageId]?.sources
        ?..clear()..addAll(completionEvent.sources!);
      __jsonLog(chatEventData["data"], tag: "CHAT ADD SOURCES"); // ??? Does this occure?
    }

    // Compat 0.5.2 > 0.5.4 -> copletionsEvent.choices is no longer relied on?
    if(completionEvent.content?.isNotEmpty == true) {
      __debugLog(completionEvent.content ?? "", tag: "UPDATE MESSAGE $messageId");
      _chat?.history[messageId]?.text = completionEvent.content;
      _responseStream?.add("");
    }

    if(completionEvent.done) {
      _endCompletion(_chat?.history[messageId]);
    }
  }

  /// The chats title has changed.
  /// Update the chat title, invoke chat list update.
  /// Updates [chatListNotifier].
  void _handleTitleEvent (Map<String, dynamic> chatEvent) {
    if(chatEvent["chat_id"] == _chat?.id) {
      _chat?.title = chatEvent["data"]?["data"];
      __debugLog(_chat?.title ?? "", tag: "CHAT TITLE CHANGED");
      _loadChatList();
    }
  }

  /// The chats tags have changed.
  /// Update the chat tags, notifies provider listeners.
  void _handleTagsEvent (Map<String, dynamic> chatEvent) {
    if(chatEvent["chat_id"] == _chat?.id) {
      final tags = chatEvent["data"]?["data"];
      __jsonLog(tags, tag: "CHAT TAGS CHANGED");
      notifyListeners();
    }
  }

  /// The message has a new status attachment.
  /// This typically occures, when for example a tool is invoked.
  void _handleStatusEvent (String messageId, Map<String, dynamic> chatEvent) {
    final messageStatusData = chatEvent["data"];
    __jsonLog(messageStatusData ?? {}, tag: "CHAT STATUS CHANGED");
    final status = OwuiStatusHistoryEntry.fromJson(messageStatusData ?? {});

    _chat?.history[messageId]?.statusHistory.add(status);

    if((_chat?.history[messageId]?.text ?? "").isEmpty) {
      /// This is so the loading status for the messages stops.
      _chat?.history[messageId]?.text = " "; // Hmmm...
    }

    _responseStream?.add("");
  }

  /// The message has a new citation attachment.
  /// This for example happens on web searches, where results are returned as citations.
  void _handleCitationEvent (String messageId, Map<String, dynamic> chatEvent) {
    final messageStatusData = chatEvent["data"];
    __jsonLog(messageStatusData ?? {}, tag: "CHAT CITATIONS CHANGED");


    _chat?.history[messageId]?.sources.add(
      OwuiDocumentSource.fromJson(messageStatusData ?? {})
    );
    
    if((_chat?.history[messageId]?.text ?? "").isEmpty) {
      _chat?.history[messageId]?.text = " "; // Hmmm...
      _responseStream?.add("");
    }
  }

  /// Uploads an attachment to the open-webui server.
  /// 
  /// [attachment] the [Attachment] to upload (from flutter_ai_toolkit).
  /// Returns an [OwuiFileAttachment] that can be attached to a [OwuiChatMessage].
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
        ..files.add(http.MultipartFile.fromBytes('file', attachment.bytes,
          filename: attachment.name,
          contentType: MediaType.parse(attachment.mimeType)
        ));

      final response = await request.send();
      
      if (response.statusCode == 200) {
        final responseBody = jsonDecode(await response.stream.bytesToString());
        __jsonLog(responseBody, tag: "FILE UPLOAD RESPONSE");
        return OwuiFileAttachment.fromJson(responseBody);
      } else {
        throw Exception('Failed to upload file: ${response.reasonPhrase}');
      }
    }
    throw Exception('Unsupported FileAttachment type: $attachment');
  }

  /// Get a list of chats from the server.
  /// This is typically called on startup and whenever the provider seems fit.
  Future<void> _loadChatList () async {
    final response = await http.get(
      Uri.parse('$_host/v1/chats/list'),
      headers: {
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final responseBody = jsonDecode(response.body);
      __jsonLog(responseBody, tag: "LOAD CHAT LIST RESPONSE");
      final chatList = OwuiChatList.fromJson(responseBody);
      // Sort the chat list by the newest
      chatList.chats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      _chats = chatList;
      chatListNotifier.value = chatList.chats;
    } else {
      throw Exception('Failed to load chats: ${response.reasonPhrase}');
    }
  }

  /// List all chats on page [page].
  Future<List<OwuiChatListEntry>> listChatsPage (int page) async {
    final response = await http.get(
      Uri.parse('$_host/v1/chats/?page=$page'),
      headers: {
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Accept': 'application/json',
      }
    );

    if(response.statusCode == 200) {
      final responseBody = jsonDecode(response.body);
      __debugLog(responseBody, tag: "LIST CHAT PAGE $page");
      return OwuiChatList.fromJson(responseBody).chats;
    } else {
      throw Exception('Failed to poll name: ${response.reasonPhrase}');
    }
  }

  /// Convert [_chat] to JSON and save it to the server.
  /// The [_chat] is **REPLACED** with the response from the server.
  /// Notifies provider listeners.
  Future<void> _saveChat () async {
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
      final jsonResponse = jsonDecode(response.body);
      __jsonLog(jsonResponse, tag: "SAVE CHAT RESPONSE");
      _chat = OwuiChat.fromJson(jsonResponse); // Avoid side effect?
      notifyListeners();
    } else {
      throw Exception('Failed to save chat: ${response.reasonPhrase}');
    }
  }

  /// Start a completion request for a message.
  /// The initial request is a http request, which is started to run parallel.
  /// The responses are handled by [_handleSocketEvent].
  void _startCompletion (OwuiChatMessage? message) {
    _incompleteMessages += 1;
    _responseStream ??= StreamController<String>.broadcast();
    
    // _socket?.add('42["usage",{"action":"chat","${message?.model}}":"deepseek-chat","chat_id":"${_chat?.id}"}]');
    
    // final llmMessage = _chat?.tail;
    final reqMessages = _chat?.messages.where((m) => (m.text ?? "").isNotEmpty).toList() ?? [];
    final body = OwuiCompletionRequest(
      model: message?.model ?? "",
      toolIds: [
        'web_search',
        // 'keyless_weather',
      ],
      features: {
        "web_search": false
      },
      chatId: _chat?.id,
      messages: reqMessages,
      id: message?.id,
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
        final jsonResponse = jsonDecode(await response.stream.bytesToString());
        __jsonLog(jsonResponse, tag: "COMPLETION RESPONSE");
      });
  }

  /// Close the completion stream if all messages are completed.
  /// This is called from [_handleCompletionEvent].
  /// 
  /// [message] the message to be completed.
  Future<void> _endCompletion (OwuiChatMessage? message) async {
    _incompleteMessages -= 1;

    if(_incompleteMessages <= 0) {
      __debugLog("$_incompleteMessages", tag: "CLOSE RESPONSE STREAM");
      _responseStream?.close();
      _responseStream = null;
      _incompleteMessages = 0;
    }
    
    message?.done = true;

    final body = {
      'model': message?.model ?? "",
      'messages': _chat?.messages.map((message) => message.toCompletedJson()).toList(),
      'chat_id': _chat?.id,
      'session_id': _sessionId,
      'id': message?.id,
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

  /// Load settings and models.
  /// This will notify all listeners.
  Future<void> _configure () async {
    if(_settings == null) {
      await _loadSettings();
    }

    if(_models == null) {
      await _loadModels();
    }
  }

  /// Load openwebui settings.
  /// 
  /// See [OwuiSettings].
  Future<void> _loadSettings() async {
    final response = await http.get(
      Uri.parse('$_host/v1/users/user/settings'),
      headers: {
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      _settings = OwuiSettings.fromJson(jsonResponse);
      modelSelection = _settings?.ui.models ?? [];
      __jsonLog(jsonResponse, tag: "SETTINGS");
      
    } else {
      throw Exception('Failed to load settings: ${response.reasonPhrase}');
    }
  }

  /// Load openwebui models.
  /// 
  /// See [OwuiLlmModelList].
  Future<void> _loadModels () async {
    final response = await http.get(
      Uri.parse('$_host/models'),
      headers: {
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      __jsonLog(jsonResponse, tag: "MODELS");
      _models = OwuiLlmModelList.fromJson(jsonResponse);
       modelListNotifier.value = _models?.models ?? [];
    } else {
      throw Exception('Failed to load models: ${response.reasonPhrase}');
    }
  }

  /// Create a normal chat request in a chat that isn't new.
  /// 
  /// FIXME: Check if [createChat] and [_streamFromUserMessage] can be unified.
  /// 
  /// [userMessage] the message to append to the chat.
  Future<void> _streamFromUserMessage (OwuiChatMessage userMessage) async {
    assert(userMessage.origin == MessageOrigin.user);

    _chat?.appendSibling(userMessage);
    final List<OwuiChatMessage> outMessages = [];

    for (final model in modelSelection) {
      final message = OwuiChatMessage.llm(
        parentId: userMessage.id,
        model: model,
        modelIdx: modelSelection.indexOf(model),
        modelName: model
      );

      _chat?.appendSibling(message);
      outMessages.add(message);
    }
    
    notifyListeners();

    for(final attachment in userMessage.attachments) {
      userMessage.files.add(await _handleAttachment(attachment));
    }
      
    for (final llmMessage in outMessages) {
      _startCompletion(llmMessage);
    }

    notifyListeners();
  }

  /// ******
  /// PUBLIC 
  /// ******


  @override
  Stream<String> generateStream(
    String prompt, {
    Iterable<Attachment> attachments = const [],
  }) async* {
    // FIXME: THIS IS CURRENTLY NOT SUPPORTED
    // Can we assume this is only called when audio is added?
    // In that case maybe rename?
    throw UnimplementedError();
  }

  @override
  Stream<String> sendMessageStream(
    String prompt, {
    Iterable<Attachment> attachments = const [],
  }) async* {
    if(_chat == null) {
      await createChat([OwuiChatMessage.user(prompt,
        attachments: attachments,
        models: modelSelection,
      )]);

      yield* _responseStream?.stream ?? Stream.empty();
    } else {
      await _streamFromUserMessage(OwuiChatMessage.user(prompt,
        attachments: attachments,
        models: modelSelection,
        parentId: _chat?.tail?.id
      ));

      yield* _responseStream?.stream ?? Stream.empty();
    }

    await _saveChat();
  }

  /// Create a new empty chat.
  /// The new instance will be stored in openwebui backend.
  /// Use this instead of setting [history] directly.
  /// 
  /// Warning! Switching back and forth between openwebui provider and other providers at runtime will save multiple copies of the chat.
  /// 
  /// [messages] the initial messages to add to the chat.
  Future<void> createChat (Iterable<ChatMessage> messages) async {
    _chat = null;
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

      _chat?.appendSibling(OwuiChatMessage(
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
      final jsonResponse = jsonDecode(response.body);
      __jsonLog(jsonResponse, tag: "CREATE CHAT RESPONSE");
      final chat = OwuiChat.fromJson(jsonResponse);
      _chat = chat;

      // Register callbacks for this chat.
      _socket?.add("43${json.encode(["usage", {
        "action": "chat",
        "model": modelSelection.first,
        "chat_id": chat.id,
      }])}");
      
      if (_chat?.tail?.origin == MessageOrigin.user) {
        final tail = _chat?.tail;
        for (final model in modelSelection) {
          final message = OwuiChatMessage.llm(
            parentId: tail?.id,
            model: model,
            modelIdx: 0,
            modelName: model
          );
          chat.appendSibling(message);
          _startCompletion(message);
        }
      }

      await _saveChat(); // required exclusively for title generation... yay!
    } else {
      throw Exception('Failed to create chat: ${response.reasonPhrase}');
    }
  }

  /// Restore [_chat] from [chatId]
  /// 
  /// get chatIds from [chats] or [chatListNotifier].
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
      final jsonResponse = jsonDecode(response.body);
      __jsonLog(jsonResponse, tag: "LOAD CHAT RESPONSE");
      _chat = OwuiChat.fromJson(jsonResponse);
      modelSelection = _chat?.models ?? [];
      _registerSocket();
      notifyListeners();
      return _chat!;
    } else {
      throw Exception('Failed to select chat: ${response.reasonPhrase}');
    }
  }

  /// Delete a chat from the server.  
  /// If no [chatId] is provided the active instance of chat is deleted.  
  /// Notifies its listeners.  
  /// Reloads the chat list.  
  /// 
  /// [chatId] optional - the id of the chat to delete.
  Future<void> deleteChat ([String? chatId]) async {
    final response = await http.delete(
      Uri.parse('$_host/v1/chats/${chatId ?? _chat?.id}'),
      headers: {
        if (_apiKey != null) 'Authorization': 'Bearer $_apiKey',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      if(_chat?.id == chatId || chatId == null) {
        _chat = null;
        notifyListeners();
        await _loadChatList();
      }
    } else {
      throw Exception('Failed to delete chat: ${response.reasonPhrase}');
    }
  }

  /// Notifies all listeners
  /// Throw away the _chat instance, without deleting it on the server.  
  /// 
  /// The next call to [sendMessageStream] will create a new chat.  
  /// Notifies all listeners.
  void clearChat () {
    _chat = null;
    notifyListeners();
    chatListNotifier.value = chats;
    modelListNotifier.value = _models?.models ?? [];
  }

  @override
  Iterable<ChatMessage> get history => _chat?.messages.cast<ChatMessage>() ?? []; // Downcast or "abort edit" will crash

  @override
  set history(Iterable<ChatMessage> newHistory) {
    if(newHistory.isEmpty && (_chat?.history.isNotEmpty ?? false)) {
      // history editing the first message.
      // Resetting [OwuiChat.historyCurrentId] like this sets the parent of the next (typically user) Message to null.
      // This means it will be a sibling to the first message.
      _chat?.historyCurrentId = "";
      return;
    } else if(newHistory.isEmpty) {
      // clear history
      // Throw the chat away.
      // The next call to [sendMessageStream] will create a new chat.
      _chat = null;
      return;
    }

    final newTail = newHistory.last;

    if(newTail is OwuiChatMessage) {
      if(_chat?.history[newTail.id] == null) {
        /// User is modifying chat in some weird way by setting history
        throw("Setting history is not supported for OpenWebUIProvider. Use [loadChat] and [createChat] instead.");
      } else {
        /// User is history editing
        _chat?.historyCurrentId = newTail.id;
      }
    } else {
      /// Init chat by setting history
      /// [createChat] will call notifyListeners multiple times during chat creation.
      createChat(newHistory);
    }
  }
}
