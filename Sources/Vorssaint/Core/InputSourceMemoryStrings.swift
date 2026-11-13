// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The words of per-application input source memory: the settings page, the
/// Features hub’s tile, and the honest note about the system’s own document
/// switching, which this feature never turns on, off, or overrides.
struct InputSourceMemoryFeatureStrings {
    let name: String
    let caption: String
    let watchingNow: String
    let applicationsRememberedFormat: String
    let nothingRemembered: String
    let systemSwitchingNote: String
}

extension FeatureStrings {
    static func inputSourceMemory(_ language: AppLanguage) -> InputSourceMemoryFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension InputSourceMemoryFeatureStrings {
    static let enUS = InputSourceMemoryFeatureStrings(
        name: "Remember Input Source Per App",
        caption: "Automatically restore the last used input source when switching applications.",
        watchingNow: "Watching applications now",
        applicationsRememberedFormat: "Remembered applications: %d",
        nothingRemembered: "Nothing is remembered yet. Switch the input source in an app, and the next visit restores it.",
        systemSwitchingNote: "macOS has its own “Automatically switch to a document’s input source”. Sadoyo never changes that setting. With both on, macOS switches per document and Sadoyo restores per application, so the source that types is the one you used last."
    )

    static let ptBR = InputSourceMemoryFeatureStrings(
        name: "Memorizar o método de entrada por app",
        caption: "Restaura automaticamente o último método de entrada usado ao trocar de aplicativo.",
        watchingNow: "Observando os aplicativos agora",
        applicationsRememberedFormat: "Aplicativos memorizados: %d",
        nothingRemembered: "Nada foi memorizado ainda. Troque o método de entrada em um app e a próxima visita o restaurará.",
        systemSwitchingNote: "O macOS tem a sua própria opção “Alternar automaticamente para o método de entrada do documento”. O Sadoyo nunca altera essa configuração. Com as duas ativas, o macOS alterna por documento e o Sadoyo restaura por aplicativo; o método que digita é o que você usou por último."
    )

    static let tr = InputSourceMemoryFeatureStrings(
        name: "Uygulama başına giriş kaynağını hatırla",
        caption: "Uygulamalar arasında geçiş yapılan son giriş kaynağını otomatik olarak geri yükler.",
        watchingNow: "Uygulamalar şimdi izleniyor",
        applicationsRememberedFormat: "Hatırlanan uygulama: %d",
        nothingRemembered: "Henüz bir şey hatırlanmadı. Bir uygulamada giriş kaynağını değiştirin, sonraki ziyarette geri yüklenir.",
        systemSwitchingNote: "macOS’un kendi “Belgenin giriş kaynağına otomatik geç” seçeneği vardır. Sadoyo bu ayarı asla değiştirmez. İkisi de açıkken macOS belgeye göre, Sadoyo uygulamaya göre geçiş yapar; böylece yazan kaynak son kullandığınızdır."
    )

    static let ru = InputSourceMemoryFeatureStrings(
        name: "Запоминать источник ввода для каждого приложения",
        caption: "Автоматически восстанавливает последний использованный источник ввода при переключении приложений.",
        watchingNow: "Сейчас следит за приложениями",
        applicationsRememberedFormat: "Запомнено приложений: %d",
        nothingRemembered: "Пока ничего не запомнено. Смените источник ввода в приложении, и следующий визит его восстановит.",
        systemSwitchingNote: "В macOS есть собственный параметр «Автоматически переключать источник ввода документа». Sadoyo его никогда не меняет. Когда включены оба, macOS переключает по документу, а Sadoyo восстанавливает по приложению, поэтому печатает тот источник, которым вы пользовались последним."
    )

    static let es = InputSourceMemoryFeatureStrings(
        name: "Recordar el método de entrada por app",
        caption: "Restaura automáticamente el último método de entrada usado al cambiar de aplicación.",
        watchingNow: "Observando las aplicaciones ahora",
        applicationsRememberedFormat: "Aplicaciones recordadas: %d",
        nothingRemembered: "Aún no se ha recordado nada. Cambia el método de entrada en una app y la próxima visita lo restaurará.",
        systemSwitchingNote: "macOS tiene su propia opción “Cambiar automáticamente al método de entrada del documento”. Sadoyo nunca cambia ese ajuste. Con ambas activas, macOS cambia por documento y Sadoyo restaura por aplicación, así que escribe el método que usaste por última vez."
    )

    static let sk = InputSourceMemoryFeatureStrings(
        name: "Pamätať si zdroj zadávania pre každú aplikáciu",
        caption: "Pri prepnutí aplikácie automaticky obnoví naposledy použitý zdroj zadávania.",
        watchingNow: "Teraz sleduje aplikácie",
        applicationsRememberedFormat: "Zapamätaných aplikácií: %d",
        nothingRemembered: "Zatiaľ nič nie je zapamätané. Zmeňte zdroj zadávania v aplikácii a nasledujúca návšteva ho obnoví.",
        systemSwitchingNote: "macOS má vlastnú voľbu “Automaticky prepnúť na zdroj zadávania dokumentu”. Sadoyo toto nastavenie nikdy nemení. Keď sú zapnuté obe, macOS prepína podľa dokumentu a Sadoyo obnovuje podľa aplikácie, takže píše zdroj, ktorý ste použili naposledy."
    )

    static let de = InputSourceMemoryFeatureStrings(
        name: "Eingabequelle pro App merken",
        caption: "Stellt beim Wechseln der Anwendung automatisch die zuletzt verwendete Eingabequelle wieder her.",
        watchingNow: "Anwendungen werden jetzt beobachtet",
        applicationsRememberedFormat: "Gemerkte Anwendungen: %d",
        nothingRemembered: "Noch ist nichts gemerkt. Wechsle die Eingabequelle in einer App, und der nächste Besuch stellt sie wieder her.",
        systemSwitchingNote: "macOS hat die eigene Option „Automatisch zur Eingabequelle des Dokuments wechseln“. Sadoyo ändert diese Einstellung nie. Sind beide aktiv, wechselt macOS je Dokument und Sadoyo stellt je Anwendung wieder her – es tippt dann die Eingabequelle, die du zuletzt verwendet hast."
    )

    static let fr = InputSourceMemoryFeatureStrings(
        name: "Mémoriser la source de saisie par app",
        caption: "Restaure automatiquement la dernière source de saisie utilisée lors du changement d’application.",
        watchingNow: "Surveille les applications maintenant",
        applicationsRememberedFormat: "%d applications mémorisées",
        nothingRemembered: "Rien n’est mémorisé pour l’instant. Changez la source de saisie dans une app et la prochaine visite la restaurera.",
        systemSwitchingNote: "macOS possède son propre réglage «\u{00A0}basculer automatiquement vers la source de saisie du document\u{00A0}». Sadoyo ne le modifie jamais. Avec les deux activés, macOS bascule par document et Sadoyo restaure par application. C’est donc la source saisie en dernier qui écrit."
    )

    static let it = InputSourceMemoryFeatureStrings(
        name: "Memorizza il sorgente di input per app",
        caption: "Ripristina automaticamente l’ultimo sorgente di input usato al cambio di applicazione.",
        watchingNow: "Ora osserva le applicazioni",
        applicationsRememberedFormat: "Applicazioni memorizzate: %d",
        nothingRemembered: "Non c’è ancora nulla di memorizzato. Cambia il sorgente di input in un’app e la prossima visita lo ripristinerà.",
        systemSwitchingNote: "macOS ha la sua opzione “Passa automaticamente al sorgente di input del documento”. Sadoyo non modifica mai quell’impostazione. Con entrambe attive, macOS passa per documento e Sadoyo ripristina per applicazione, quindi scrive l’ultimo sorgente usato."
    )

    static let ja = InputSourceMemoryFeatureStrings(
        name: "アプリごとに入力ソースを記憶",
        caption: "アプリを切り替えるとき、最後に使った入力ソースを自動的に復元します。",
        watchingNow: "いまアプリを監視しています",
        applicationsRememberedFormat: "記憶したアプリ: %d",
        nothingRemembered: "まだ何も記憶していません。アプリで入力ソースを切り替えると、次回そのソースに戻ります。",
        systemSwitchingNote: "macOS には「書類の入力ソースに自動的に切り替える」という設定があります。Sadoyo はその設定を変更しません。両方がオンのとき、macOS は書類ごとに切り替え、Sadoyo はアプリごとに復元するので、最後に使った入力ソースで入力できます。"
    )

    static let ko = InputSourceMemoryFeatureStrings(
        name: "앱별 입력 소스 기억",
        caption: "앱을 전환할 때 마지막으로 사용한 입력 소스를 자동으로 복원합니다.",
        watchingNow: "지금 앱을 살핍니다",
        applicationsRememberedFormat: "기억한 앱: %d",
        nothingRemembered: "아직 기억한 것이 없습니다. 앱에서 입력 소스를 바꾸면 다음에 그 소스로 돌아옵니다.",
        systemSwitchingNote: "macOS에는 “문서의 입력 소스로 자동 전환” 항목이 있습니다. Sadoyo는 그 설정을 바꾸지 않습니다. 둘 다 켜면 macOS는 문서별로 전환하고 Sadoyo는 앱별로 복원하므로, 마지막에 사용한 입력 소스로 입력합니다."
    )

    static let zhHans = InputSourceMemoryFeatureStrings(
        name: "按应用记忆输入法",
        caption: "切换应用时自动恢复该应用上次使用的输入法。",
        watchingNow: "正在监视应用",
        applicationsRememberedFormat: "已记忆的应用：%d",
        nothingRemembered: "尚未记住任何应用。在某个应用里切换输入法后，下次进入时会自动恢复。",
        systemSwitchingNote: "macOS 自带“自动切换到文稿的输入法”。Sadoyo 不会更改该设置。两者同时开启时，macOS 按文稿切换，Sadoyo 按应用恢复，因此输入的是你最后使用的那个。"
    )

    static let zhTW = InputSourceMemoryFeatureStrings(
        name: "依 App 記憶輸入法",
        caption: "切換 App 時自動恢復上次使用的輸入法。",
        watchingNow: "正在監看 App",
        applicationsRememberedFormat: "已記憶的 App：%d",
        nothingRemembered: "尚未記住任何 App。在某個 App 裡切換輸入法後，下次進入時會自動恢復。",
        systemSwitchingNote: "macOS 自帶「自動切換至文件輸入法」。Sadoyo 不會更改該設定。兩者同時開啟時，macOS 依文件切換，Sadoyo 依 App 恢復，因此輸入的是你最後使用的那個。"
    )

    static let zhHK = InputSourceMemoryFeatureStrings(
        name: "依 App 記憶輸入法",
        caption: "切換 App 時自動恢復上次使用的輸入法。",
        watchingNow: "正在監看 App",
        applicationsRememberedFormat: "已記憶的 App：%d",
        nothingRemembered: "尚未記住任何 App。在某個 App 裡切換輸入法後，下次進入時會自動恢復。",
        systemSwitchingNote: "macOS 自帶「自動切換至文件輸入法」。Sadoyo 不會更改該設定。兩者同時開啟時，macOS 依文件切換，Sadoyo 依 App 恢復，因此輸入的是你最後使用的那個。"
    )

    static let uk = InputSourceMemoryFeatureStrings(
        name: "Запам’ятовувати джерело введення для кожної програми",
        caption: "Автоматично відновлює останнє використане джерело введення під час перемикання програм.",
        watchingNow: "Зараз стежить за програмами",
        applicationsRememberedFormat: "Запам’ято програм: %d",
        nothingRemembered: "Поки що нічого не запам’ятано. Змініть джерело введення у програмі, і наступний візит його відновить.",
        systemSwitchingNote: "У macOS є власний параметр «Автоматично перемикати джерело введення документа». Sadoyo його ніколи не змінює. Коли увімкнені обидва, macOS перемикає за документом, а Sadoyo відновлює за програмою, тому друкує те джерело, яким ви користувалися останнім."
    )
}
