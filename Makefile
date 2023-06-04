
DOCKER_IMAGE_NAME := curl-with-http3

all: build

build:
	docker image build --tag $(DOCKER_IMAGE_NAME):latest .
