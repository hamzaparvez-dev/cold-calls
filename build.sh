#!/bin/bash
set -e

echo "Installing Bundler 2.0+..."
gem install bundler -v '~> 2.0'

echo "Installing gems..."
bundle install --without development test

echo "Build completed successfully!"

