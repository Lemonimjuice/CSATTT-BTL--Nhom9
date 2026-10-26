package com.blogapi.util;

import java.text.Normalizer;
import java.util.Locale;
import java.util.regex.Pattern;

public final class SlugUtils {

    private static final Pattern NON_ASCII   = Pattern.compile("[^\\p{ASCII}]");
    private static final Pattern NOT_ALNUM   = Pattern.compile("[^a-z0-9\\-]");
    private static final Pattern MULTI_DASH  = Pattern.compile("-{2,}");
    private static final Pattern EDGE_DASH   = Pattern.compile("(^-|-$)");

    private SlugUtils() {}

    public static String toSlug(String input) {
        if (input == null) return "";
        String normalized = Normalizer.normalize(input, Normalizer.Form.NFD);
        String ascii  = NON_ASCII.matcher(normalized).replaceAll("");
        String lower  = ascii.toLowerCase(Locale.ROOT).trim().replace(' ', '-');
        String clean  = NOT_ALNUM.matcher(lower).replaceAll("");
        String single = MULTI_DASH.matcher(clean).replaceAll("-");
        return EDGE_DASH.matcher(single).replaceAll("");
    }
}
