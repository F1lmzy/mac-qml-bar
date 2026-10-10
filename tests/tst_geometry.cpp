#include <QtTest>
#include "../src/geometry.h"

class GeometryTest : public QObject {
    Q_OBJECT
private slots:
    void topCentreIsStable() {
        const QRect screen(1440, -200, 1920, 1080);
        QCOMPARE(pillFrame(screen, QSize(250, 34), 8), QRect(2275, -192, 250, 34));
        QCOMPARE(pillFrame(screen, QSize(440, 264), 8), QRect(2180, -192, 440, 264));
    }
    void roundedCornersPassThrough() {
        QVERIFY(!pillContains(QSizeF(250, 34), QPointF(0, 0)));
        QVERIFY(pillContains(QSizeF(250, 34), QPointF(125, 17)));
        QVERIFY(pillContains(QSizeF(440, 264), QPointF(220, 263)));
        QVERIFY(!pillContains(QSizeF(250, 34), QPointF(-1, 17)));
        QVERIFY(!pillContains(QSizeF(250, 34), QPointF(250, 17)));
    }
};
QTEST_GUILESS_MAIN(GeometryTest)
#include "tst_geometry.moc"
