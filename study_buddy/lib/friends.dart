// adapted from the following tutorial https://heartbeat.fritz.ai/firebase-user-authentication-in-flutter-1635fb175675
// synchronous and asynchronous validator set up is adapted from https://medium.com/@nocnoc/the-secret-to-async-validation-on-flutter-forms-4b273c667c03
// filtering is based on this tutorial https://medium.com/@thedome6/how-to-create-a-searchable-filterable-listview-in-flutter-4faf3e300477

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:email_validator/email_validator.dart';

import './customCard.dart';

class Friends extends StatefulWidget {
  Friends({Key key, this.uid, this.date}) : super(key: key);

  final String uid;
  final String date;

  @override
  _FriendsState createState() => _FriendsState();
}

class _FriendsState extends State<Friends> {
  final GlobalKey<FormState> _friendFormKey = GlobalKey<FormState>();
  TextEditingController taskTitleInputController;
  String filter;
  List<String> emails = [];
  List<String> tmpEmailsArray = [];
  var recipient;

  bool _isInvalidAsyncEmail = false;
  bool _haveValidEmail = false;

  String _emailOfRecipient;

  bool _haveData = false;
  String _senderFullName;
  String _senderEmail;

  @override
  initState() {
    // TODO: commenting out the following text edit line
    taskTitleInputController = new TextEditingController();

    getUserInfo();
    super.initState();
  }

  void getUserInfo() {

    Firestore.instance.collection("users").getDocuments().then((docs) {
      setState(() {
        docs.documents.forEach((doc) {
          emails.add(
              doc["email"] + " (" + doc["fname"] + " " + doc["surname"] + ")");
          if (doc["uid"] == widget.uid) {
            _senderFullName = doc["fname"] + " " + doc["surname"];

            _senderEmail = doc["email"];
          }
        });
        _haveData = true;
      });
    });
  }

  // TODO: I don't know if the following is necessary
  @override
  void dispose() {
    taskTitleInputController.dispose();
    super.dispose();
  }

  String emailValidator(String value) {
    if (!EmailValidator.validate(value.trim())) {
      return "Email format is invalid";
    }
    if (value.toLowerCase().trim() == _senderEmail) {
      return "Can't send friend request to yourself";
    }
    if (_isInvalidAsyncEmail) {
      _isInvalidAsyncEmail = false;
      return "This email doesn't exist";

    }
    return null;
  }

  _showDialog() async {
    _isInvalidAsyncEmail = false;
    _haveValidEmail = false;

    // run the validators on reload to process async results
    _friendFormKey.currentState?.validate();
    await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        contentPadding: const EdgeInsets.all(16.0),
        content: Column(
          children: <Widget>[
            Text("Please fill all fields to create a new friend request"),
            Form(
                key: _friendFormKey,
                child: Column(
                  children: <Widget>[
                    TextFormField(
                      decoration: InputDecoration(
                          labelText: 'Email', hintText: "john.doe@gmail.com"),
                      controller: taskTitleInputController,
                      keyboardType: TextInputType.emailAddress,
                      validator: emailValidator,
                      onSaved: (value) =>
                          _emailOfRecipient = value.toLowerCase().trim(),
                    ),
                    Container(
                      width: double.maxFinite,
                      child: SizedBox(
                          height: 150.0,
                          child: new MyDialogContent(
                            emails: emails,
                            textController: taskTitleInputController,
                          )),
                    )
                  ],
                )),
          ],
        ),
        actions: <Widget>[
          FlatButton(
              child: Text('Cancel'),
              onPressed: () {
                taskTitleInputController.clear();

                Navigator.pop(context);
              }),
          FlatButton(
              child: Text('Add'),
              onPressed: () {
                if (_friendFormKey.currentState.validate()) {
                  _friendFormKey.currentState.save();

                  // dismiss keyboard during async call
                  FocusScope.of(context).requestFocus(new FocusNode());

                  Firestore.instance
                      .collection("users")
                      .where("email", isEqualTo: _emailOfRecipient)
                      .getDocuments()
                      .then((QuerySnapshot docs) {
                    if (docs.documents.isNotEmpty) {
                      // emails are unique, so there should only be one
                      recipient = docs.documents[0].data;

                      _isInvalidAsyncEmail = false;

                      Firestore.instance
                          .collection("users")
                          .document(recipient["uid"])
                          .collection('friends')
                          .add({
                        "uid": widget.uid,
                        "status": "incoming",
                        "fullName": _senderFullName,
                        "email": _senderEmail,
                        "date": widget.date
                      }).catchError((err) => print(err));

                      Firestore.instance
                          .collection("users")
                          .document(widget.uid)
                          .collection('friends')
                          .add({
                            "uid": recipient["uid"],
                            "status": "pending",
                            "fullName":
                                recipient["fname"] + " " + recipient["surname"],
                            "email": taskTitleInputController.text,
                            "date": widget.date
                          })
                          .then((result) => {
                                Navigator.pop(context),
                                taskTitleInputController.clear(),
                              })
                          .catchError((err) => print(err));
                    } else {
                      _isInvalidAsyncEmail = true;
                      _friendFormKey.currentState.validate();
                    }
                  });
                }
              })
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_haveData) {
      return Column(children: <Widget>[
        Expanded(
          child: SizedBox(
              child: StreamBuilder<QuerySnapshot>(
            stream: Firestore.instance
                .collection("users")
                .document(widget.uid)
                .collection('friends')
                .orderBy("status")
                .snapshots(),
            builder:
                (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
              if (snapshot.hasError)
                return new Text('Error: ${snapshot.error}');
              switch (snapshot.connectionState) {
                case ConnectionState.waiting:
                  return new Text('Loading...');
                default:
                  return new ListView(
                    children: snapshot.data.documents
                        .map((DocumentSnapshot document) {
                      return new CustomCard(
                        name: document['fullName'],
                        email: document['email'],
                        date: document['date'],
                        status: document['status'],
                        uid: document["uid"],
                        docId: document.documentID,
                        userEmail: _senderEmail,
                        userFullName: _senderFullName,
                        userUID: widget.uid,
                      );
                    }).toList(),
                  );
              }
            },
          )),
        ),
        RaisedButton(
          onPressed: _showDialog,
          child: Icon(Icons.add),
        )
      ]);
    } else {
      return Center(
        child: CircularProgressIndicator(
          valueColor: new AlwaysStoppedAnimation(Colors.blue),
        ),
      );
    }
  }
}

class MyDialogContent extends StatefulWidget {
  MyDialogContent({Key key, this.emails, this.textController})
      : super(key: key);

  List<String> emails;
  TextEditingController textController;

  @override
  _MyDialogContentState createState() => new _MyDialogContentState();
}

class _MyDialogContentState extends State<MyDialogContent> {
  String filter;

  @override
  void initState() {
    //widget.textController = new TextEditingController();
    widget.textController.addListener(() {
      if (!mounted) {
        return;
      }
      setState(() {
        filter = widget.textController.text;
      });
    });
    super.initState();
  }

  @override
  void dispose() {
    // TODO: implement dispose
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TODO: implement build

    return ListView.builder(
      itemCount: widget.emails.length,
      itemBuilder: (BuildContext context, int index) {
        return (filter == null || filter == "")
            ? new Card(child: new Text(widget.emails[index]))
            : widget.emails[index].toLowerCase().contains(filter.toLowerCase())
                ? new Card(child: new Text(widget.emails[index]))
                : new Container();
      },
    );
  }
}
