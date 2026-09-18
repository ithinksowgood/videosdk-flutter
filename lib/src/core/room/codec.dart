// ignore_for_file: constant_identifier_names

/// Video codecs supported for camera tracks.
///
/// Pass a value to [VideoSDK.createCameraVideoTrack] (or related APIs) to
/// produce video using the chosen codec.
enum VideoCodec {
  /// Provides good video quality with low CPU usage, broad compatibility,
  /// and support for multiStream.
  VP8,

  /// Offers high-quality video compression for modern devices while
  /// requiring moderate to high CPU resources.
  VP9,

  /// Delivers excellent video quality and compression efficiency, with
  /// support continuing to expand across browsers and devices.
  ///
  /// > **Note:** AV1 has limited support. Test it on your target browsers and devices
  /// > before using it.
  AV1,

  /// Provides good video quality with low CPU usage, broad device
  /// support, and support for multiStream.
  H264,
}

extension CodecExtension on VideoCodec {
  String parseToString() => name;

  static VideoCodec parseToEnum(String codec) {
    switch (codec.toUpperCase()) {
      case 'VP8':
        return VideoCodec.VP8;
      case 'VP9':
        return VideoCodec.VP9;
      case 'AV1':
        return VideoCodec.AV1;
      case 'H264':
        return VideoCodec.H264;
      default:
        return VideoCodec.VP8;
    }
  }
}
