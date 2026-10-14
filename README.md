# Ella

App Android em Flutter para acompanhar o ciclo menstrual com identidade visual própria e cores vibrantes. “Meu ciclo” guarda os registros da pessoa que acompanha o próprio ciclo; “Compartilhado” conecta duas contas por convite.

## Recursos disponíveis

- Calendário interativo para marcar ou remover o início e o fim da menstruação.
- Estimativas locais de ciclo, menstruação e janela fértil; a duração registrada do fluxo é respeitada no calendário.
- Diário do dia com humor, fluxo, sintomas e observação opcional.
- Lembrete local na véspera da próxima previsão, às 9h, com permissão de notificações do Android.
- Registros armazenados localmente com `flutter_secure_storage`.
- Convite de uso único com código aleatório de 10 caracteres, válido por 30 minutos.
- Atualização automática em tempo real do ciclo e diário para a conta convidada, em modo de consulta.
- Opção para encerrar o compartilhamento. Os registros pessoais da conta convidada não são enviados à outra pessoa.

## Firebase Authentication e Cloud Firestore

O app está configurado para o projeto Firebase **Ella** (`ella-50a33`), no plano Spark, com o banco Firestore em São Paulo (`southamerica-east1`). Authentication usa **e-mail/senha**. Analytics e Gemini ficaram desativados.

Na tela inicial, toque no ícone de conta para criar uma conta ou entrar. A cópia pessoal do Firestore só é enviada ao tocar em **Enviar cópia para a nuvem**. O código de convite compartilha apenas o ciclo da pessoa que o criou, com a outra conta tendo acesso de leitura. A configuração Android está em `android/app/google-services.json`.

Para ativar o pareamento no projeto, publique as regras atualizadas de `firestore.rules` com uma sessão autenticada do Firebase CLI:

```powershell
firebase deploy --only firestore:rules --project ella-50a33
```

Para instalar as dependências e executar:

```powershell
& 'C:\flutter\bin\flutter.bat' pub get
& 'C:\flutter\bin\flutter.bat' run
```

Depois da publicação das regras, as duas pessoas precisam instalar o app, entrar em contas distintas e usar **Criar código de convite** e **Inserir código recebido** na área Compartilhado.

## Executar

Na pasta do projeto, com Flutter instalado:

```powershell
& 'C:\flutter\bin\flutter.bat' pub get
& 'C:\flutter\bin\flutter.bat' run
```

## Gerar APK

```powershell
& 'C:\flutter\bin\flutter.bat' build apk --release
```

O arquivo sai em `build/app/outputs/flutter-apk/app-release.apk`.

## Limites

O intervalo padrão da previsão é de 28 dias e ainda não pode ser ajustado. As datas e a janela fértil são estimativas, não devem ser usadas como método contraceptivo ou orientação médica. Lembretes são locais e dependem da permissão de notificações e das restrições de segundo plano do aparelho. A sincronização compartilhada depende de conexão à internet e da publicação das regras Firestore incluídas neste projeto.
