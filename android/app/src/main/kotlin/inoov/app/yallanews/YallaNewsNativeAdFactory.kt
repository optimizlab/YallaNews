package inoov.app.yallanews

import android.content.Context
import android.graphics.Color
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.RatingBar
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.NativeAdFactory

/**
 * Factory that renders [NativeAd]s inside Flutter PlatformViews.
 *
 * The layout used is `res/layout/native_ad_layout.xml`. Flutter requests ads
 * with the factory id "yallanewsNativeAd", which is registered in MainActivity.
 */
class YallaNewsNativeAdFactory(private val context: Context) : NativeAdFactory {

    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: Map<String, Any>?,
    ): NativeAdView {
        val adView = LayoutInflater.from(context)
            .inflate(R.layout.native_ad_layout, null) as NativeAdView

        val iconView = adView.findViewById<ImageView>(R.id.ad_icon)
        val headlineView = adView.findViewById<TextView>(R.id.ad_headline)
        val bodyView = adView.findViewById<TextView>(R.id.ad_body)
        val advertiserView = adView.findViewById<TextView>(R.id.ad_advertiser)
        val mediaView = adView.findViewById<com.google.android.gms.ads.nativead.MediaView>(R.id.ad_media)
        val ctaView = adView.findViewById<Button>(R.id.ad_call_to_action)
        val starsView = adView.findViewById<RatingBar>(R.id.ad_stars)
        val priceView = adView.findViewById<TextView>(R.id.ad_price)
        val badgeView = adView.findViewById<TextView>(R.id.ad_badge)

        // Keep the dark-mode text legible when the app runs a dark theme.
        badgeView.setTextColor(Color.parseColor("#8E8E93"))

        adView.headlineView = headlineView
        adView.bodyView = bodyView
        adView.iconView = iconView
        adView.advertiserView = advertiserView
        adView.mediaView = mediaView
        adView.callToActionView = ctaView
        adView.starRatingView = starsView
        adView.priceView = priceView

        headlineView.text = nativeAd.headline ?: ""
        headlineView.setTextColor(Color.parseColor("#F1F5F9"))

        bodyView.text = nativeAd.body ?: ""
        bodyView.setTextColor(Color.parseColor("#CBD5E1"))

        advertiserView.text = nativeAd.advertiser ?: ""
        advertiserView.setTextColor(Color.parseColor("#94A3B8"))

        ctaView.text = nativeAd.callToAction ?: "Learn more"
        priceView.text = nativeAd.price ?: ""

        starsView.rating = nativeAd.starRating?.toFloat() ?: 0f
        if (nativeAd.starRating == null) {
            starsView.visibility = View.GONE
        }

        if (nativeAd.icon == null) {
            iconView.visibility = View.GONE
        } else {
            iconView.visibility = View.VISIBLE
            iconView.setImageDrawable(nativeAd.icon?.drawable)
        }

        // Dark native card: keeps ad text legible over any in-app surface and
        // visually separates sponsored content from real news cards.
        adView.setBackgroundColor(Color.parseColor("#FF1E293B"))

        // Track impressions/engagements for the native ad.
        adView.setNativeAd(nativeAd)

        return adView
    }
}
