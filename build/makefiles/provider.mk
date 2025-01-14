# provider.mk
#
# common rules for building capability providers
# Some of these rules depend on GNUMakefile >= 4.0
#
# before including this, local project makefile should define the following
# (to override defaults)
# top_targets      # list of targets that are applicable for this project
#

top_targets     ?= all build par clean

platform_id = $(shell uname -s)
platform = $$( \
	case $(platform_id) in \
		( Linux | Darwin ) echo $(platform_id) ;; \
		( * ) echo Unrecognized Platform;; \
	esac )

machine_id = $(shell uname -m )

# name of compiled binary
bin_name ?= $(PROJECT)
dest_par ?= build/$(bin_name).par.gz

link_name ?= default

# If name is not defined, used project
NAME ?= $(PROJECT)

WASH ?= wash

oci_url_base ?= localhost:5000/v2
oci_url      ?= $(oci_url_base)/$(bin_name):$(VERSION)
ifeq ($(WASH_REG_USER),)
	oci_insecure := --insecure
endif

par_targets ?= \
	x86_64-unknown-linux-gnu \
   	x86_64-apple-darwin \
	armv7-unknown-linux-gnueabihf \
   	aarch64-unknown-linux-gnu \
   	aarch64-apple-darwin \
   	x86_64-pc-windows-gnu

bin_targets = $(foreach target,$(par_targets),target/$(target)/release/$(bin_name))

# pick target0 for starting par
ifeq ($(machine_id)-$(platform_id),x86_64-Linux)
	par_target0 = x86_64-unknown-linux-gnu
else
	ifeq ($(machine_id)-$(platform_id),x86_64-Darwin)
		par_target0 = x86_64-apple-darwin
	else
		# default to x86_64-linux
		par_target0=x86_64-unknown-linux-gnu
	endif
endif

# the target of the current platform, as defined by cross
cross_target0=target/$(par_target0)/release/$(bin_name)
# bin_target0=$(cross_target0)
bin_target0=target/release/$(bin_name)

# traverse subdirs
.ONESHELL:
ifneq ($(subdirs),)
$(top_targets)::
	for dir in $(subdirs); do \
		$(MAKE) -C $$dir $@ weld=$(weld); \
	done
endif

# default target
all:: $(dest_par)

par:: $(dest_par)

# rebuild base par if target0 changes
$(dest_par): $(bin_target0) Makefile Cargo.toml
	@mkdir -p $(dir $(dest_par))
	par_arch=`echo $(par_target0) | sed -E 's/([^-]+)-([^-]+)-([^-]+)(-gnu)?/\1-\3/'`
	$(WASH) par create \
		--arch $$par_arch \
		--binary $(bin_target0) \
		--capid $(CAPABILITY_ID) \
		--name $(NAME) \
		--vendor $(VENDOR) \
		--version $(VERSION) \
		--revision $(REVISION) \
		--destination $@ \
		--compress
	@echo Created $@


# par-full adds all the other targets to the base par
par-full: $(dest_par) $(bin_targets)
	# add other defined targets
	for target in $(par_targets); do \
	    target_dest=target/$$target/release/$(bin_name);  \
	    par_arch=`echo -n $$target | sed -E 's/([^-]+)-([^-]+)-([^-]+)(-gnu)?/\1-\3/'`; \
		echo building $$par_arch; \
		if [ $${target_dest} != $(cross_target0) ] && [ -f $$target_dest ]; then \
		    $(WASH) par insert --arch $$par_arch --binary $$target_dest $@; \
		fi; \
	done

# create rust build targets
ifeq ($(wildcard ./Cargo.toml),./Cargo.toml)

# rust dependencies
RUST_DEPS += $(wildcard src/*.rs) $(wildcard target/*/deps/*) Cargo.toml Makefile

target/release/$(bin_name): $(RUST_DEPS)
	cargo build --release

target/debug/$(bin_name): $(RUST_DEPS)
	cargo build

# cross-compile target
target/%/release/$(bin_name): $(RUST_DEPS)
	tname=`echo -n $@ | sed -E 's_target/([^/]+)/release.*$$_\1_'` &&\
	cross build --release --target $$tname

endif

# push par file to registry
push: $(dest_par)
	$(WASH) reg push $(oci_insecure) $(oci_url) $(dest_par)




# start provider
start:
	$(WASH) ctl start provider $(oci_url) \
		--host-id $(shell $(WASH) ctl get hosts -o json | jq -r ".hosts[0].id") \
		--link-name $(link_name) \
		--timeout 4

# inspect claims on par file
inspect: $(dest_par)
	$(WASH) par inspect $(dest_par)

inventory:
	$(WASH) ctl get inventory $(shell $(WASH) ctl get hosts -o json | jq -r ".hosts[0].id")

clean::
	rm -rf build/

ifeq ($(wildcard ./Cargo.toml),./Cargo.toml)
build::
	cargo build

release::
	cargo build --release

clean::
	cargo clean
	cross clean || echo
endif


# for debugging - show variables make is using
make-vars:
	@echo "weld:          : $(weld)"
	@echo "platform_id    : $(platform_id)"
	@echo "platform       : $(platform)"
	@echo "machine_id     : $(machine_id)"
	@echo "default-par    : $(par_target0)"
	@echo "project_dir    : $(project_dir)"
	@echo "subdirs        : $(subdirs)"
	@echo "top_targets    : $(top_targets)"
	@echo "NAME           : $(NAME)"
	@echo "VENDOR         : $(VENDOR)"
	@echo "VERSION        : $(VERSION)"
	@echo "REVISION       : $(REVISION)"


.PHONY: all build release par clean test $(weld)
