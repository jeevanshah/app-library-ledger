import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  BannerAd? _bannerAd;
  InterstitialAd? _interstitialAd;
  bool _isBannerLoaded = false;
  bool _isInterstitialLoaded = false;
  bool _adsRemoved = false;

  // Test ad unit IDs — replace with real IDs before production
  static const String _bannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111'; // Test ID
  static const String _interstitialAdUnitId = 'ca-app-pub-3940256099942544/1033173712'; // Test ID

  bool get adsRemoved => _adsRemoved;
  bool get isBannerLoaded => _isBannerLoaded;

  void setAdsRemoved(bool value) {
    _adsRemoved = value;
    if (value) {
      _bannerAd?.dispose();
      _bannerAd = null;
      _isBannerLoaded = false;
      _interstitialAd?.dispose();
      _interstitialAd = null;
      _isInterstitialLoaded = false;
    }
  }

  Future<void> init() async {
    await MobileAds.instance.initialize();
    if (!_adsRemoved) {
      loadBannerAd();
      loadInterstitialAd();
    }
  }

  void loadBannerAd() {
    if (_adsRemoved) return;
    _bannerAd?.dispose();
    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => _isBannerLoaded = true,
        onAdFailedToLoad: (ad, error) {
          _isBannerLoaded = false;
          ad.dispose();
        },
      ),
    );
    _bannerAd!.load();
  }

  void loadInterstitialAd() {
    if (_adsRemoved) return;
    _interstitialAd?.dispose();
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialLoaded = true;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (_) {
              _isInterstitialLoaded = false;
              loadInterstitialAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _isInterstitialLoaded = false;
              loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (_) {
          _isInterstitialLoaded = false;
        },
      ),
    );
  }

  void showInterstitialAd() {
    if (_adsRemoved || !_isInterstitialLoaded) return;
    _interstitialAd?.show();
  }

  BannerAd? get bannerAd => _bannerAd;

  static const String removeAdsProductId = 'remove_ads';
}