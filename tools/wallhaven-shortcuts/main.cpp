#include <QAction>
#include <QFile>
#include <QGuiApplication>
#include <QProcess>
#include <QStandardPaths>

#include <KGlobalAccel>
#include <KLocalizedString>

static QString ctlPath()
{
    const QByteArray env = qgetenv("WALLHAVEN_CTL");
    if (!env.isEmpty()) {
        return QString::fromLocal8Bit(env);
    }
    const QStringList candidates = {
        QStandardPaths::writableLocation(QStandardPaths::HomeLocation)
            + QStringLiteral("/.local/share/wallhaven-plasma/tools/wallhaven-ctl.sh"),
        QStringLiteral("/usr/share/wallhaven-plasma/tools/wallhaven-ctl.sh"),
    };
    for (const QString &path : candidates) {
        if (QFile::exists(path)) {
            return path;
        }
    }
    return candidates.constFirst();
}

static void runCtl(const QString &cmd)
{
    const QString ctl = ctlPath();
    QProcess::startDetached(QStringLiteral("bash"), {ctl, cmd});
}

// Meta+Alt+Left/Right/P clash with KWin "Switch Window" and plasmashell
// "cycle-panels", so the defaults moved to Meta+Ctrl+Alt (free in stock Plasma).
static void registerShortcut(QGuiApplication &app, const QString &name, const QString &text,
                             const QString &cmd, int key)
{
    auto action = new QAction(text, &app);
    action->setObjectName(name);
    QObject::connect(action, &QAction::triggered, [cmd] { runCtl(cmd); });

    const QKeySequence preferred(Qt::META | Qt::CTRL | Qt::ALT | key);
    const QKeySequence legacy(Qt::META | Qt::ALT | key);
    KGlobalAccel::setGlobalShortcut(action, preferred);
    // setGlobalShortcut keeps the saved binding; move only untouched legacy defaults.
    if (KGlobalAccel::self()->shortcut(action) == QList<QKeySequence>{legacy}) {
        KGlobalAccel::self()->setShortcut(action, {preferred}, KGlobalAccel::NoAutoloading);
    }
}

int main(int argc, char *argv[])
{
    // QAction lives in QtGui in Qt 6: a QCoreApplication segfaults on the first new QAction.
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("wallhaven-shortcuts"));
    // Without a desktop file name Qt registers an empty app id with the desktop
    // portal and logs "Could not register app ID: App info not found for ''".
    QGuiApplication::setDesktopFileName(QStringLiteral("wallhaven-shortcuts"));
    QGuiApplication::setQuitOnLastWindowClosed(false);
    KLocalizedString::setApplicationDomain("org.robertsm.wallhaven");

    registerShortcut(app, QStringLiteral("wallhaven-next"), i18n("Wallhaven Next Wallpaper"),
                     QStringLiteral("next"), Qt::Key_Right);
    registerShortcut(app, QStringLiteral("wallhaven-prev"), i18n("Wallhaven Previous Wallpaper"),
                     QStringLiteral("prev"), Qt::Key_Left);
    registerShortcut(app, QStringLiteral("wallhaven-pause"), i18n("Wallhaven Pause Slideshow"),
                     QStringLiteral("pause"), Qt::Key_P);
    registerShortcut(app, QStringLiteral("wallhaven-reload"), i18n("Wallhaven Reload Wallpaper"),
                     QStringLiteral("reload"), Qt::Key_R);

    return app.exec();
}
