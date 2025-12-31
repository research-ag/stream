import Text "mo:core/Text";

module {
  public type HttpRequest = {
    method : Text;
    url : Text;
    headers : [(Text, Text)];
    body : Blob;
  };

  public type HttpResponse = {
    status_code : Nat16;
    headers : [(Text, Text)];
    body : Blob;
  };

  public func render400() : HttpResponse = {
    status_code : Nat16 = 400;
    headers : [(Text, Text)] = [];
    body : Blob = "Invalid request";
  };

  public func renderPlainText(text : Text) : HttpResponse = {
    status_code = 200;
    headers = [("content-type", "text/plain")];
    body = Text.encodeUtf8(text);
  };
};
