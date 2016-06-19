.PHONY: all deps clean release

all: compile

compile: deps
	./rebar -j8 compile

deps:
	./rebar -j8 get-deps

clean:
	./rebar -j8 clean

relclean:
	rm -rf rel/yunba_mqtt_serialiser

generate: compile
	cd rel && .././rebar -j8 generate

run: generate
	./rel/yunba_mqtt_serialiser/bin/yunba_mqtt_serialiser start

console: generate
	./rel/yunba_mqtt_serialiser/bin/yunba_mqtt_serialiser console

foreground: generate
	./rel/yunba_mqtt_serialiser/bin/yunba_mqtt_serialiser foreground

erl: compile
	erl -pa ebin/ -pa deps/*/ebin/ -s yunba_mqtt_serialiser
