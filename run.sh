rm -rf doc/api
dart pub global activate dartdoc
export PATH="$PATH:$HOME/.pub-cache/bin"
dartdoc
python3 -m http.server 8000 -d doc/api