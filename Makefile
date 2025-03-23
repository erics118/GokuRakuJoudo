GRAALVM_ARG=--initialize-at-build-time
JAR_NAME=karabiner-configurator-0.1.0-standalone
TARGET_JAR=target/$(JAR_NAME).jar
all:
	$(MAKE) clean
	$(MAKE) compile
	$(MAKE) bin
clean:
	lein clean
compile:
	lein compile && export LEIN_SNAPSHOTS_IN_RELEASE=override && lein uberjar
bin:
	native-image $(GRAALVM_ARG) -jar $(TARGET_JAR)
	mv $(JAR_NAME) goku
	chmod +x goku
test-binary:
	mkdir -p ~/.config/karabiner
	cp ./resources/configurations/edn/yqrashawn.edn ~/.config/karabiner.edn
	cp ./resources/configurations/json/empty-karabiner.json ~/.config/karabiner/karabiner.json
	./goku
