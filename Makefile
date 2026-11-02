.PHONY: build simulator lint test

build:
	packaging/dev/build-ios.sh

simulator:
	packaging/dev/build-simulator.sh

lint:
	python3 packaging/dev/lint.py

test:
	python3 packaging/dev/check-models.py
	python3 -m unittest discover -s packaging/release -p 'test_*.py'
	python3 -m unittest discover -s lab/iphoneintents -p 'test_*.py'
	python3 -m unittest discover -s lab/iphone-real -p 'test_*.py'
