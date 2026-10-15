FLAVOR ?= acme
BRANDS := acme globex

#     make build-android-appBundle                  # Avera
#     make build-android-appBundle FLAVOR=acme      # acme
#     make build-android-appBundle FLAVOR=globex    # globex
#     make build-android-appBundle-all              # every brand

.PHONY: run
run:
	flutter run --flavor $(FLAVOR) --dart-define-from-file=config/$(FLAVOR)/production.json


.PHONY: _appbundle
_appbundle:
	flutter build appbundle --release --flavor $(FLAVOR) \
		--dart-define-from-file=config/$(FLAVOR)/production.json
	mkdir -p build/release/$(FLAVOR)
	cp build/app/outputs/bundle/$(FLAVOR)Release/app-$(FLAVOR)-release.aab build/release/$(FLAVOR)/


.PHONY: build-appbundle-all
build-appbundle-all:
	@for brand in $(BRANDS); do $(MAKE) _appbundle FLAVOR=$$brand || exit 1; done

.PHONY: build-appbundle
build-appbundle:
	@flutter clean 
	@flutter pub get
	$(MAKE) --no-print-directory _appbundle FLAVOR=$(FLAVOR)