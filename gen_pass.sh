#!/bin/bash

generate_password() {
    read -p "Яка кількість символів? " SYMBOLS
    openssl rand -base64 ${SYMBOLS} | tr -d '/+=' | cut -c1-${SYMBOLS}
}

generate_password
