#include <QAction>
#include <QCoreApplication>
#include <QFile>
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

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    KLocalizedString::setApplicationDomain("org.robertsm.wallhaven");

    auto next = new QAction(i18n("Wallhaven Next Wallpaper"), &app);
    QObject::connect(next, &QAction::triggered, [] { runCtl(QStringLiteral("next")); });
    KGlobalAccel::setGlobalShortcut(next, QKeySequence(Qt::META | Qt::ALT | Qt::Key_Right));

    auto prev = new QAction(i18n("Wallhaven Previous Wallpaper"), &app);
    QObject::connect(prev, &QAction::triggered, [] { runCtl(QStringLiteral("prev")); });
    KGlobalAccel::setGlobalShortcut(prev, QKeySequence(Qt::META | Qt::ALT | Qt::Key_Left));

    auto pause = new QAction(i18n("Wallhaven Pause Slideshow"), &app);
    QObject::connect(pause, &QAction::triggered, [] { runCtl(QStringLiteral("pause")); });
    KGlobalAccel::setGlobalShortcut(pause, QKeySequence(Qt::META | Qt::ALT | Qt::Key_P));

    auto reload = new QAction(i18n("Wallhaven Reload Wallpaper"), &app);
    QObject::connect(reload, &QAction::triggered, [] { runCtl(QStringLiteral("reload")); });
    KGlobalAccel::setGlobalShortcut(reload, QKeySequence(Qt::META | Qt::ALT | Qt::Key_R));

    return app.exec();
}
