# Agenda ST Bertioga

Repositorio de distribuicao e builds mobile do Agenda ST Bertioga.

## iOS

O projeto Xcode fica em `ios/AgendaSTBertioga.xcodeproj`.

O primeiro workflow do Codemagic gera um build **sem assinatura para o simulador**, suficiente para validar que o projeto compila em macOS/Xcode sem pagar Apple Developer.

A interface carrega o Hosting oficial `https://agenda-externa-st.web.app/` em `WKWebView` e ja possui bridge nativo para:

- Face ID / Touch ID via LocalAuthentication;
- localizacao precisa via Core Location;
- limite de precisao de 100 m;
- deteccao de localizacao simulada quando o iOS informa essa origem;
- comparacao de geofence com latitude, longitude e raio recebidos da aplicacao web;
- identificador local derivado do IDFV.

### Seguranca

A Jornada no iOS deve continuar **fail-closed** ate configurarmos App Attest/DeviceCheck com uma conta Apple Developer e ajustarmos o Hosting para aceitar explicitamente `ios-native`. O projeto nao falsifica integridade do aparelho apenas para liberar ponto.
