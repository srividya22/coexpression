TOP_DIR = ../..
DEPLOY_RUNTIME?=/kb/runtime
TARGET ?= /kb/deployment
include $(TOP_DIR)/tools/Makefile.common
SERVICE_SPEC = CoExpression.spec
SERVICE_NAME = CoExpression
SERVICE_PSGI_FILE = $(SERVICE_NAME).psgi
SERVICE_DIR = $(TARGET)/services/$(SERVICE_NAME)
SERVER_MODULE = lib/Bio/KBase/$(SERVICE_NAME)/Service.pm
#SERVICE = CoExpressionService
SERVICE_PORT = 7063

TPAGE = $(DEPLOY_RUNTIME)/bin/tpage
TPAGE_ARGS = --define kb_top=$(TARGET) --define kb_runtime=$(DEPLOY_RUNTIME) --define kb_service_name=$(SERVICE_NAME) \
        --define kb_service_port=$(SERVICE_PORT)

#include $(TOP_DIR)/tools/Makefile.common

# to wrap scripts and deploy them to $(TARGET)/bin using tools in
# the dev_container. right now, these vars are defined in
# Makefile.common, so it's redundant here.
TOOLS_DIR = $(TOP_DIR)/tools
WRAP_PERL_TOOL = wrap_perl
WRAP_PERL_SCRIPT = bash $(TOOLS_DIR)/$(WRAP_PERL_TOOL).sh
SRC_PERL = $(wildcard scripts/*.pl)

WRAP_RSCRIPT_TOOL = wrap_rscript
WRAP_RSCRIPT_SCRIPT = bash $(TOOLS_DIR)/$(WRAP_RSCRIPT_TOOL).sh
SRC_R = $(wildcard scripts/*.R)

WRAP_PYTHON_TOOL = wrap_python
WRAP_PYTHON_SCRIPT = bash $(TOOLS_DIR)/$(WRAP_PYTHON_TOOL).sh
SRC_PYTHON = $(wildcard scripts/*.py)

# You can change these if you are putting your tests somewhere
# else or if you are not using the standard .t suffix
CLIENT_TESTS = $(wildcard t/client-tests/*.t)
SCRIPT_TESTS = $(wildcard t/script-tests/*.t)
SERVER_TESTS = $(wildcard t/server-tests/*.t)

# This is a very client centric view of release engineering.
# We assume our primary product for the community is the client
# libraries and command line interfaces on which specific 
# science applications can be built.
#
# A service is composed of a client and a server, each of which
# should be independently deployable. Clients are composed of
# an application programming interface and a command line
# interface. In our make targets, the deploy-service deploys
# the server, the deploy-client deploys the application
# programming interface libraries, and the deploy-scripts deploys
# the command line interface (usually scripts written in a
# scripting language but java executables also qualify), and the
# deploy target would be equivelant to deploying a service (client
# libs, scripts, and server).
#
# Because the deployment of the server side code depends on the
# specific software module being deployed, the strategy needs
# to be one that leaves this decision to the module developer.
# This is done by having the deploy target depend on the
# deploy-service target. The module developer who chooses for
# good reason not to deploy the server with the client simply
# manages this dependancy accordingly. One option is to have
# a deploy-service target that does nothing, the other is to
# remove the dependancy from the deploy target.
#
# A smiliar naming convention is used for tests. 


default: build-libs

# Test Section

test: test-client test-scripts 
	echo "running client and script tests"

# test-all is deprecated. 
# test-all: test-client test-scripts test-service
#
# What does it mean to test a client. This is a test of a client
# library. If it is a client-server module, then it should be
# run against a running server. You can say that this also tests
# the server, and I agree. You can add a test-service dependancy
# to the test-client target if it makes sense to you. This test
# example assumes there is already a tested running server.
test-client:
	# run each test
	for t in $(CLIENT_TESTS) ; do \
		if [ -f $$t ] ; then \
			$(DEPLOY_RUNTIME)/bin/perl $$t ; \
			if [ $$? -ne 0 ] ; then \
				exit 1 ; \
			fi \
		fi \
	done

# What does it mean to test a script? A script test should test
# the command line scripts. If the script is a client in a client-
# server architecture, then there should be tests against a 
# running server. You can add a test-service dependancy to the
# test-client target. You could also add a deploy-service and
# start-server dependancy to the test-scripts target if it makes
# sense to you. Future versions of the make files for services
# will move in this direction.
test-scripts:
	# run each test
	for t in $(SCRIPT_TESTS) ; do \
		if [ -f $$t ] ; then \
			$(DEPLOY_RUNTIME)/bin/perl $$t ; \
			if [ $$? -ne 0 ] ; then \
				exit 1 ; \
			fi \
		fi \
	done

# What does it mean to test a server. A server test should not
# rely on the client libraries or scripts in so far as you should
# not have a test-service target that depends on the test-client
# or test-scripts targets. Otherwise, a circular dependency
# graph could result.
test-server:
	# run each test
	for t in $(SERVER_TESTS) ; do \
		if [ -f $$t ] ; then \
			$(DEPLOY_RUNTIME)/bin/perl $$t ; \
			if [ $$? -ne 0 ] ; then \
				exit 1 ; \
			fi \
		fi \
	done


include $(TOP_DIR)/tools/Makefile.common.rules

# here are the standard KBase deployment targets (deploy,deploy-client, deploy-scripts, & deploy-service)

deploy: deploy-libs deploy-scripts deploy-service deploy-r-scripts


# Deploy client artifacts, including the application programming interface
# libraries, command line scripts, and associated reference documentation.

deploy-client: deploy-libs deploy-scripts deploy-docs

# Deploy command line scripts.  The scripts are "wrapped" so users do not
# need to modify their environment to run KBase scripts.

# Deploy documentation of the application programming interface.
# (Waiting for resolution on documentation of command line scripts).
        
deploy-docs: build-docs
	if [ ! -d $(SERVICE_DIR)/webroot ] ; then mkdir -p $(SERVICE_DIR)/webroot ; fi
	cp docs/*html $(SERVICE_DIR)/webroot/.
        
build-docs:
	if [ ! -d docs ] ; then mkdir -p docs ; fi
	pod2html -t "CoExpression" lib/Bio/KBase/CoExpression/Client.pm > docs/CoExpression.html
        
# Deploy service start and stop scripts.

deploy-service: deploy-cfg
	if [ ! -d $(SERVICE_DIR) ] ; then mkdir -p $(SERVICE_DIR) ; fi
	tpage $(TPAGE_ARGS) service/start_service.tt > $(SERVICE_DIR)/start_service; \
	chmod +x $(SERVICE_DIR)/start_service; \
	tpage $(TPAGE_ARGS) service/stop_service.tt > $(SERVICE_DIR)/stop_service; \
	chmod +x $(SERVICE_DIR)/stop_service; \
	tpage $(TPAGE_ARGS) service/process.tt > $(SERVICE_DIR)/process.$(SERVICE_NAME); \
	chmod +x $(SERVICE_DIR)/process.$(SERVICE_NAME); 
	mkdir -p $(SERVICE_DIR)/awf
	cat deploy.cfg service.cfg > $(SERVICE_DIR)/service.cfg;

# the above service.cfg is not correct at the moment
# Use this if you want to unlink the generation of the docs from
# the generation of the libs. Not recommended, but could be a
# reason for it that I'm not seeing.
# The compile-docs should depend on build-libs so that we are ensured
# of having a set of documentation that is based on the latest
# type spec.

# Build libs should be dependent on the type specification and the
# type compiler. Building the libs in this way means that you don't
# need to put automatically generated code in a source code version
# control repository (ie cvs, git). It also ensures that you always
# have the most  up-to-date libs and documentation if your compile
# docs depends on the compiled libs.
build-libs:
	mkdir -p scripts; compile_typespec \
		--psgi $(SERVICE_PSGI_FILE) \
		--impl Bio::KBase::$(SERVICE_NAME)::$(SERVICE_NAME)Impl \
		--service Bio::KBase::$(SERVICE_NAME)::Service \
		--client Bio::KBase::$(SERVICE_NAME)::Client \
		--py biokbase/$(SERVICE_NAME)/Client \
		--js javascript/$(SERVICE_NAME)/Client \
		$(SERVICE_SPEC) lib

#		--scripts scripts \ # script is not working
