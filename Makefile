PKGS := $(shell glide nv)
ORG := keratin
PROJECT := authn-server
NAME := $(ORG)/$(PROJECT)
VERSION := 1.2.0
MAIN := main.go routing.go

.PHONY: clean
clean:
	rm -rf vendor
	rm -rf dist
	rm -f api/views/*.ego.go

# Process .ego templates (skippable)
EGOS := $(shell find . -name *.ego | sed -e s/.ego/.ego.go/)
$(EGOS):
	ego api/views

# Fetch dependencies
vendor: glide.yaml
	glide install
	go install

# The Linux builder is a Docker container because that's the easiest way to get the toolchain for
# CGO on a MacOS host.
.PHONY: linux-builder
linux-builder:
	docker build -f Dockerfile.builder -t $(NAME)-builder .

# The Linux target is built using a special Docker image, because this Makefile assumes the host
# machine is running MacOS.
dist/linux/amd64/$(PROJECT): $(EGOS) vendor
	make linux-builder
	docker run --rm \
		-v $(PWD):/go/src/github.com/$(NAME) \
		-w /go/src/github.com/$(NAME) \
		$(NAME)-builder \
		sh -c " \
			GOOS=linux GOARCH=amd64 CGO_ENABLED=1 go build -ldflags '-extldflags -static -X main.VERSION=$(VERSION)' -o '$@' \
		"
	bzip2 -c "$@" > dist/authn-linux64.bz2

# The Darwin target is built using the host machine, which this Makefile assumes is running MacOS.
dist/darwin/amd64/$(PROJECT): $(EGOS) vendor
	GOOS=darwin GOARCH=amd64 CGO_ENABLED=1 go build -ldflags "-X main.VERSION=$(VERSION)" -o "$@"
	bzip2 -c "$@" > dist/authn-macos64.bz2

# The Docker target wraps the linux/amd64 binary
.PHONY: dist/docker
dist/docker: dist/linux/amd64/$(PROJECT)
	docker build --tag $(NAME):latest .

# Build all distributables
.PHONY: dist
dist: dist/docker dist/darwin/amd64/$(PROJECT) dist/linux/amd64/$(PROJECT)

# Run the server
.PHONY: server
server: $(EGOS) vendor
	docker-compose up -d redis
	DATABASE_URL=sqlite3://localhost/dev \
		REDIS_URL=redis://127.0.0.1:8701/11 \
		go run -ldflags "-X main.VERSION=$(VERSION)" $(MAIN)

# Run tests
.PHONY: test
test: $(EGOS) vendor
	docker-compose up -d redis mysql
	TEST_REDIS_URL=redis://127.0.0.1:8701/12 \
	  TEST_MYSQL_URL=mysql://root@127.0.0.1:8702/authnservertest \
	  go test $(PKGS)

# Run CI tests
.PHONY: test-ci
test-ci: $(EGOS) vendor
	TEST_REDIS_URL=redis://127.0.0.1/1 \
	  TEST_MYSQL_URL=mysql://root@127.0.0.1/test \
	  go test -race $(PKGS)

# Run benchmarks
.PHONY: benchmarks
benchmarks:
	docker-compose up -d redis
	TEST_REDIS_URL=redis://127.0.0.1:8701/12 \
		go test -run=XXX -bench=. \
			github.com/keratin/authn-server/api/meta \
			github.com/keratin/authn-server/api/sessions

# Run migrations
.PHONY: migrate
migrate:
	docker-compose up -d redis
	DATABASE_URL=sqlite3://localhost/dev \
		REDIS_URL=redis://127.0.0.1:8701/11 \
		go run -ldflags "-X main.VERSION=$(VERSION)" $(MAIN) migrate

# Cut a release of the current version.
.PHONY: release
release: test dist
	docker push $(NAME):latest
	docker tag $(NAME):latest $(NAME):$(VERSION)
	docker push $(NAME):$(VERSION)
	git tag v$(VERSION)
	git push --tags
	open https://github.com/$(NAME)/releases/tag/v$(VERSION)
	open dist
