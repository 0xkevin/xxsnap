#include <QtTest/QtTest>

#include "snipory/core/capture/CaptureTypes.h"

class TestCaptureTypes final : public QObject {
    Q_OBJECT

private slots:
    void regionFromDevicePixelsIsValid()
    {
        const snipory::core::CaptureRegion region =
            snipory::core::CaptureRegion::fromDevicePixels(1, 2, 30, 40);

        QCOMPARE(region.devicePixelRect(), QRect(1, 2, 30, 40));
        QVERIFY(region.isValid());
    }
};

QTEST_MAIN(TestCaptureTypes)
#include "TestCaptureTypes.moc"
