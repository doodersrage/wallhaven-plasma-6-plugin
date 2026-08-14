#include <QAction>
#include <QCoreApplication>
#include <QProcess>
#include <QStandardPaths>

#include <KGlobalAccel>
#include <KLocalizedString>

static void runCtl(const QString &cmd)
{
    const QString ctl = qEnvironmentVariable("WALLHAVEN_CTL",
        QCoreApplication::applicationDirPath() + QStringLiteral("/../wallhaven-ctl.sh"));
    QProcess::startDetached(QStringLiteral("bash"), {ctl, cmd});
}

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    KLocalizedString::setApplicationDomain("wallhaven-shortcuts");

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
