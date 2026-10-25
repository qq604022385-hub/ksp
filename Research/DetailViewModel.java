package com.shenma.tvlauncher.phone.viewmodel;

import android.util.Log;
import androidx.p002lifecycle.MutableLiveData;
import androidx.p002lifecycle.ViewModelKt;
import com.google.gson.Gson;
import com.shenma.tvlauncher.Api;
import com.shenma.tvlauncher.domain.Json;
import com.shenma.tvlauncher.entity.ServerEntity;
import com.shenma.tvlauncher.phone.base.BaseViewModel;
import com.shenma.tvlauncher.utils.f;
import com.shenma.tvlauncher.utils.g;
import com.shenma.tvlauncher.vod.domain.VideoDetailInfo;
import j8.k;
import j8.n0;
import java.io.IOException;
import java.net.URLEncoder;
import java.util.LinkedHashMap;
import kotlin.coroutines.jvm.internal.m;
import kotlin.jvm.functions.Function2;
import kotlin.jvm.internal.y;
import m7.f0;
import m7.q;
import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.Response;
import okhttp3.ResponseBody;
import q7.e;

/* JADX INFO: compiled from: r8-map-id-19b4395d7d83c7414f9484d07362dc20cbff117efb203cb6b96ce9c1323205ab */
/* JADX INFO: loaded from: classes5.dex */
public final class a extends BaseViewModel {

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    private final String f36064b = "DetailPlayViewModel";

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    private final MutableLiveData f36065c = new MutableLiveData();

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    private final MutableLiveData f36066d = new MutableLiveData();

    /* JADX INFO: renamed from: com.shenma.tvlauncher.phone.viewmodel.a$a, reason: collision with other inner class name */
    /* JADX INFO: compiled from: r8-map-id-19b4395d7d83c7414f9484d07362dc20cbff117efb203cb6b96ce9c1323205ab */
    static final class C0625a extends m implements Function2 {

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        int f36067b;

        /* JADX INFO: renamed from: c, reason: collision with root package name */
        final /* synthetic */ String f36068c;

        /* JADX INFO: renamed from: d, reason: collision with root package name */
        final /* synthetic */ a f36069d;

        /* JADX INFO: renamed from: com.shenma.tvlauncher.phone.viewmodel.a$a$a, reason: collision with other inner class name */
        /* JADX INFO: compiled from: r8-map-id-19b4395d7d83c7414f9484d07362dc20cbff117efb203cb6b96ce9c1323205ab */
        public static final class C0626a implements Callback {

            /* JADX INFO: renamed from: a, reason: collision with root package name */
            final /* synthetic */ a f36070a;

            C0626a(a aVar) {
                this.f36070a = aVar;
            }

            @Override // okhttp3.Callback
            public void onFailure(Call call, IOException e10) {
                y.f(call, "call");
                y.f(e10, "e");
                Log.e(this.f36070a.f36064b, "getDetailData: onFailure");
                this.f36070a.c().postValue(null);
            }

            @Override // okhttp3.Callback
            public void onResponse(Call call, Response response) {
                VideoDetailInfo videoDetailInfo;
                String strString;
                y.f(call, "call");
                y.f(response, "response");
                Log.d(this.f36070a.f36064b, "-------getDetailData code:" + response.code());
                if (response.code() == 200) {
                    ResponseBody responseBodyBody = response.body();
                    if (responseBodyBody == null || (strString = responseBodyBody.string()) == null) {
                        strString = "";
                    }
                    Object objFromJson = new Gson().fromJson(strString, (Class<Object>) VideoDetailInfo.class);
                    y.e(objFromJson, "fromJson(...)");
                    videoDetailInfo = (VideoDetailInfo) objFromJson;
                } else {
                    videoDetailInfo = null;
                }
                this.f36070a.c().postValue(videoDetailInfo);
            }
        }

        /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
        C0625a(String str, a aVar, e eVar) {
            super(2, eVar);
            this.f36068c = str;
            this.f36069d = aVar;
        }

        @Override // kotlin.coroutines.jvm.internal.a
        public final e create(Object obj, e eVar) {
            return new C0625a(this.f36068c, this.f36069d, eVar);
        }

        @Override // kotlin.jvm.functions.Function2
        public final Object invoke(n0 n0Var, e eVar) {
            return ((C0625a) create(n0Var, eVar)).invokeSuspend(f0.f45267a);
        }

        @Override // kotlin.coroutines.jvm.internal.a
        public final Object invokeSuspend(Object obj) {
            r7.b.e();
            if (this.f36067b != 0) {
                throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
            }
            q.b(obj);
            try {
                f.a(com.shenma.tvlauncher.phone.b.f35867a.c() + "/api.php/localhost/vod/?ac=detail&ids=" + this.f36068c, new C0626a(this.f36069d));
            } catch (IOException e10) {
                e10.printStackTrace();
                Log.e(this.f36069d.f36064b, "getDetailData: " + e10.getMessage());
            }
            return f0.f45267a;
        }
    }

    /* JADX INFO: compiled from: r8-map-id-19b4395d7d83c7414f9484d07362dc20cbff117efb203cb6b96ce9c1323205ab */
    static final class b extends m implements Function2 {

        /* JADX INFO: renamed from: b, reason: collision with root package name */
        int f36071b;

        /* JADX INFO: renamed from: c, reason: collision with root package name */
        final /* synthetic */ String f36072c;

        /* JADX INFO: renamed from: d, reason: collision with root package name */
        final /* synthetic */ String f36073d;

        /* JADX INFO: renamed from: e, reason: collision with root package name */
        final /* synthetic */ String f36074e;

        /* JADX INFO: renamed from: f, reason: collision with root package name */
        final /* synthetic */ String f36075f;

        /* JADX INFO: renamed from: g, reason: collision with root package name */
        final /* synthetic */ a f36076g;

        /* JADX INFO: renamed from: com.shenma.tvlauncher.phone.viewmodel.a$b$a, reason: collision with other inner class name */
        /* JADX INFO: compiled from: r8-map-id-19b4395d7d83c7414f9484d07362dc20cbff117efb203cb6b96ce9c1323205ab */
        public static final class C0627a implements Callback {

            /* JADX INFO: renamed from: a, reason: collision with root package name */
            final /* synthetic */ a f36077a;

            C0627a(a aVar) {
                this.f36077a = aVar;
            }

            @Override // okhttp3.Callback
            public void onFailure(Call call, IOException e10) {
                y.f(call, "call");
                y.f(e10, "e");
                Log.e(this.f36077a.f36064b, "getVideoUrl: " + e10.getMessage());
                this.f36077a.d().postValue(null);
            }

            @Override // okhttp3.Callback
            public void onResponse(Call call, Response response) {
                String strString;
                y.f(call, "call");
                y.f(response, "response");
                Log.d(this.f36077a.f36064b, "getVideoUrl success code: " + response.code());
                if (response.code() != 200) {
                    this.f36077a.d().postValue(null);
                    return;
                }
                ResponseBody responseBodyBody = response.body();
                if (responseBodyBody == null || (strString = responseBodyBody.string()) == null) {
                    strString = "";
                }
                ServerEntity serverEntityD = com.shenma.tvlauncher.phone.b.f35867a.d();
                String strD = g.d(strString, serverEntityD != null ? serverEntityD.getMiyao() : null);
                Log.d(this.f36077a.f36064b, "getVideoUrl decode: " + strD);
                this.f36077a.d().postValue((Json) new Gson().fromJson(strD, Json.class));
            }
        }

        /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
        b(String str, String str2, String str3, String str4, a aVar, e eVar) {
            super(2, eVar);
            this.f36072c = str;
            this.f36073d = str2;
            this.f36074e = str3;
            this.f36075f = str4;
            this.f36076g = aVar;
        }

        @Override // kotlin.coroutines.jvm.internal.a
        public final e create(Object obj, e eVar) {
            return new b(this.f36072c, this.f36073d, this.f36074e, this.f36075f, this.f36076g, eVar);
        }

        @Override // kotlin.jvm.functions.Function2
        public final Object invoke(n0 n0Var, e eVar) {
            return ((b) create(n0Var, eVar)).invokeSuspend(f0.f45267a);
        }

        @Override // kotlin.coroutines.jvm.internal.a
        public final Object invokeSuspend(Object obj) {
            r7.b.e();
            if (this.f36071b != 0) {
                throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
            }
            q.b(obj);
            try {
                String strEncode = URLEncoder.encode(this.f36072c + "-" + this.f36073d, "UTF-8");
                LinkedHashMap linkedHashMap = new LinkedHashMap();
                String str = "&account=520720&password=520720&series=" + strEncode + "&edition=2.9";
                linkedHashMap.put(com.anythink.core.common.f.a.C0157a.f5431c, Api.f35718a);
                com.shenma.tvlauncher.phone.b bVar = com.shenma.tvlauncher.phone.b.f35867a;
                ServerEntity serverEntityD = bVar.d();
                linkedHashMap.put(com.anythink.core.common.f.e.a.f5457b, g.f(str, serverEntityD != null ? serverEntityD.getRck() : null));
                f.b(bVar.b() + "/Client" + this.f36074e + "/?url=" + this.f36075f, new C0627a(this.f36076g), linkedHashMap, null);
            } catch (IOException e10) {
                e10.printStackTrace();
            }
            return f0.f45267a;
        }
    }

    public final void b(String id) {
        y.f(id, "id");
        k.d(ViewModelKt.getViewModelScope(this), null, null, new C0625a(id, this, null), 3, null);
    }

    public final MutableLiveData c() {
        return this.f36065c;
    }

    public final MutableLiveData d() {
        return this.f36066d;
    }

    public final void e(String videoName, String url, String title, String clientNumber) {
        y.f(videoName, "videoName");
        y.f(url, "url");
        y.f(title, "title");
        y.f(clientNumber, "clientNumber");
        k.d(ViewModelKt.getViewModelScope(this), null, null, new b(videoName, title, clientNumber, url, this, null), 3, null);
    }
}
