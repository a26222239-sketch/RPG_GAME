using System;
using System.IO;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;

public static class BattleUiArt {
 static string input, output;
 static Color C(string h) { return ColorTranslator.FromHtml(h); }
 static int Cl(double v) { return Math.Max(0,Math.Min(255,(int)Math.Round(v))); }
 static Bitmap Load(string p) { return new Bitmap(p); }
 static void Save(Bitmap b,string rel) { string p=Path.Combine(output,rel); Directory.CreateDirectory(Path.GetDirectoryName(p)); b.Save(p,ImageFormat.Png); }
 static Graphics G(Bitmap b) { var g=Graphics.FromImage(b); g.InterpolationMode=InterpolationMode.HighQualityBicubic; g.PixelOffsetMode=PixelOffsetMode.HighQuality; g.SmoothingMode=SmoothingMode.AntiAlias; g.TextRenderingHint=TextRenderingHint.AntiAliasGridFit; return g; }
 static void Draw(Graphics g,Image b,RectangleF d) { g.DrawImage(b,d); }
 static void Nine(Graphics g,Bitmap b,RectangleF d,int m) {
  int[] sx={0,m,b.Width-m,b.Width}, sy={0,m,b.Height-m,b.Height};
  float[] dx={d.Left,d.Left+m,d.Right-m,d.Right},dy={d.Top,d.Top+m,d.Bottom-m,d.Bottom};
  for(int y=0;y<3;y++)for(int x=0;x<3;x++)g.DrawImage(b,new RectangleF(dx[x],dy[y],dx[x+1]-dx[x],dy[y+1]-dy[y]),new RectangleF(sx[x],sy[y],sx[x+1]-sx[x],sy[y+1]-sy[y]),GraphicsUnit.Pixel);
 }
 static void Text(Graphics g,string text,float size,Color color,RectangleF r,bool center=false) {
  using(var f=new Font("PMingLiU",size,FontStyle.Regular,GraphicsUnit.Pixel))
  using(var br=new SolidBrush(color))
  using(var sf=new StringFormat()){sf.Alignment=center?StringAlignment.Center:StringAlignment.Near;sf.LineAlignment=StringAlignment.Center; sf.FormatFlags=StringFormatFlags.NoWrap | StringFormatFlags.NoClip; g.DrawString(text,f,br,r,sf);}
 }
 static Color Sample(Bitmap b,int cx,int cy,int w,int h) {
  double r=0,g=0,bl=0,n=0;
  for(int y=cy-h/2;y<cy+h/2;y++)for(int x=cx-w/2;x<cx+w/2;x++){var c=b.GetPixel(x,y);if(c.A>240){r+=c.R;g+=c.G;bl+=c.B;n++;}}
  return Color.FromArgb(Cl(r/n),Cl(g/n),Cl(bl/n));
 }
 static void Buttons(Bitmap atlas) {
  using(var original=Load(Path.Combine(input,"button.png"))) {
   string[] names={"button_disabled","button_pressed","button_active"};
   for(int k=0;k<3;k++) {
    using(var result=new Bitmap(original.Width,original.Height,PixelFormat.Format32bppArgb)) {
     var target=Sample(atlas,new int[]{272,768,1264}[k],200,180,60);
     for(int y=0;y<original.Height;y++)for(int x=0;x<original.Width;x++) {
      var s=original.GetPixel(x,y); if(s.A==0){result.SetPixel(x,y,s);continue;}
      double r=s.R,gr=s.G,b=s.B;
      bool bronze=s.R>s.G*1.03 && s.R>s.B*1.10;
      if(k==0) {
       double l=.2126*r+.7152*gr+.0722*b;
       r=(r*.28+l*.72)*.56; gr=(gr*.28+l*.72)*.57; b=(b*.28+l*.72)*.59;
      } else if(k==1) {
       double f=.72+.18*y/(original.Height-1.0);
       r*=f;gr*=f;b*=f;
       if(!bronze){r=r*.6+target.R*.4;gr=gr*.6+target.G*.4;b=b*.6+target.B*.4;}
      } else if(bronze) {
       double l=(.2126*r+.7152*gr+.0722*b)/157.0;
       r=229*l;gr=199*l;b=136*l;
      } else { r=r*.68+target.R*.45; gr=gr*.68+target.G*.45; b=b*.68+target.B*.45; }
      result.SetPixel(x,y,Color.FromArgb(s.A,Cl(r),Cl(gr),Cl(b)));
     }
     Save(result,"ui/"+names[k]+".png");
    }
   }
  }
 }
 static Bitmap Track(Bitmap atlas) {
  using(var crop=atlas.Clone(new Rectangle(88,414,650,50),PixelFormat.Format32bppArgb)) {
   var b=new Bitmap(384,20,PixelFormat.Format32bppArgb);
   using(var g=G(b)){
    // Keep end caps proportional; only extend the horizontal middle.
    g.DrawImage(crop,new Rectangle(0,0,20,20),new Rectangle(0,0,50,50),GraphicsUnit.Pixel);
    g.DrawImage(crop,new Rectangle(20,0,344,20),new Rectangle(50,0,550,50),GraphicsUnit.Pixel);
    g.DrawImage(crop,new Rectangle(364,0,20,20),new Rectangle(600,0,50,50),GraphicsUnit.Pixel);
   }
   for(int y=0;y<20;y++)for(int x=0;x<384;x++){
    var c=b.GetPixel(x,y);int a=Cl((c.A-96)*255.0/128.0); b.SetPixel(x,y,Color.FromArgb(a,c.R,c.G,c.B));
   }
   return b;
  }
 }
 static Bitmap Fill(Color color) {
  var b=new Bitmap(384,20,PixelFormat.Format32bppArgb);
  using(var g=G(b))
  using(var path=new GraphicsPath()) {
   path.AddPolygon(new PointF[]{new PointF(10,10),new PointF(16,4),new PointF(368,4),new PointF(374,10),new PointF(368,16),new PointF(16,16)});
   using(var br=new LinearGradientBrush(new Rectangle(0,4,384,12),ControlPaint(color,1.12),ControlPaint(color,.82),90f))g.FillPath(br,path);
  }
  return b;
 }
 static Color ControlPaint(Color c,double m){return Color.FromArgb(Cl(c.R*m),Cl(c.G*m),Cl(c.B*m));}
 static void Bars(Bitmap atlas) {
  using(var track=Track(atlas)){Save(track,"ui/mp_track.png");Save(track,"ui/gauge_track.png");}
  using(var mp=Fill(C("#7BB9B0")))Save(mp,"ui/mp_fill.png");
  using(var gauge=Fill(C("#D9B872")))Save(gauge,"ui/gauge_fill.png");
 }
 static void DrawBar(Graphics g,string track,string fill,RectangleF rect,float ratio) {
  using(var t=Load(Path.Combine(output,track)))g.DrawImage(t,rect);
  var old=g.Save();
  // Fill sources have 10px horizontal empty margins; reveal only the inner span.
  g.SetClip(new RectangleF(rect.X,rect.Y,(10+364*ratio)/384*rect.Width,rect.Height),CombineMode.Intersect);
  using(var f=Load(Path.Combine(output,fill)))g.DrawImage(f,rect);
  g.Restore(old);
 }
 static void Hp(Graphics g,RectangleF rect,float ratio) {
  using(var t=Load(Path.Combine(input,"ui_hp_track.png")))g.DrawImage(t,rect);
  var old=g.Save();g.SetClip(new RectangleF(rect.X,rect.Y,(10+364*ratio)/384*rect.Width,rect.Height),CombineMode.Intersect);
  using(var f=Load(Path.Combine(input,"ui_hp_fill.png")))g.DrawImage(f,rect);g.Restore(old);
 }
 static void Actor(Graphics g,string id,float x,float foot,int frame,bool flip) {
  using(var b=Load(Path.Combine(input,"characters_"+id+"_frames_stand.png"))){
   if(flip)b.RotateFlip(RotateFlipType.RotateNoneFlipX);
   using(var shadow=new SolidBrush(Color.FromArgb(55,10,17,20)))g.FillEllipse(shadow,x-frame*.14f,foot-7,frame*.28f,18);
   g.DrawImage(b,new RectangleF(x-frame/2f,foot-(frame-32),frame,frame));
  }
 }
 static void Preview() {
  using(var b=new Bitmap(1920,1080,PixelFormat.Format32bppArgb))
  using(var g=G(b))
  using(var bg=Load(Path.Combine(input,"backgrounds_battle_tianmo_hall.jpg")))
  using(var panel=Load(Path.Combine(input,"ui_panel.png")))
  using(var normal=Load(Path.Combine(input,"button.png")))
  using(var disabled=Load(Path.Combine(output,"ui/button_disabled.png")))
  using(var active=Load(Path.Combine(output,"ui/button_active.png"))) {
   g.Clear(C("#172C34"));g.DrawImage(bg,new RectangleF((1920-2560*1.04f)/2,(1080-1080*1.04f)/2,2560*1.04f,1080*1.04f));
   Actor(g,"wen_peak",1920*.11f,782,512,false);
   Actor(g,"shen_peak",1920*.315f,780,512,false);
   Actor(g,"huo_peak",1920*.215f,830,512,false);
   Actor(g,"yanhui_peak",1920*.42f,830,512,false);
   Actor(g,"tianmo",1920*.775f,832,768,true);
   Color paper=C("#EAE3CF"),dim=C("#81918E");
   Nine(g,panel,new RectangleF(30,24,600,264),48);
   string[] ids={"yanhui_peak","shen_peak","huo_peak","wen_peak"}, names={"燕回","沈清禾","霍嶽","溫蘅"},hp={"8330","6724","10120","8600"};
   float[] hpr={.85f,.82f,.88f,1f},mpr={1f,1f,1f,1f};
   for(int i=0;i<4;i++){
    float y=43+i*58;
    using(var head=Load(Path.Combine(input,"characters_"+ids[i]+"_portrait_head.png"))){
     using(var br=new SolidBrush(C("#31565B")))g.FillRectangle(br,50,y,48,48);
     g.DrawImage(head,new RectangleF(50,y,48,48));
     using(var pen=new Pen(C("#B89A66"),1))g.DrawRectangle(pen,50,y,48,48);
    }
    Text(g,names[i],32,paper,new RectangleF(112,y-1,122,52));
    Hp(g,new RectangleF(245,y+2,248,25),hpr[i]);
    DrawBar(g,"ui/mp_track.png","ui/mp_fill.png",new RectangleF(245,y+32,248,14),mpr[i]);
    Text(g,hp[i],34,paper,new RectangleF(505,y,105,50),true);
   }
   Nine(g,panel,new RectangleF(774,24,748,96),48);
   using(var p=new SolidBrush(C("#EC8174")))g.FillPolygon(p,new PointF[]{new PointF(815,59),new PointF(827,71),new PointF(815,83),new PointF(803,71)});
   Text(g,"殷九淵",36,paper,new RectangleF(844,37,150,64));
   Hp(g,new RectangleF(996,57,389,28),.86f);
   Text(g,"86%",40,paper,new RectangleF(1400,37,100,64),true);
   Nine(g,normal,new RectangleF(1670,24,220,84),28);
   Text(g,"跳過序章",34,paper,new RectangleF(1675,24,210,84),true);
   Nine(g,panel,new RectangleF(665,133,705,142),48);
   Text(g,"威力大的招式要先蓄力，也會消耗內力。",34,paper,new RectangleF(689,151,657,48),true);
   Text(g,"按下「雲棧・千仞」",38,paper,new RectangleF(689,202,657,48),true);
   DrawBar(g,"ui/gauge_track.png","ui/gauge_fill.png",new RectangleF(1920*.315f-66,358,132,12),1f);
   using(var br=new SolidBrush(C("#72ABE3")))g.FillPolygon(br,new PointF[]{new PointF(585,310),new PointF(625,310),new PointF(605,343)});
   string[] moves={"點星","斷流","雲棧飛花","輕身訣","雲棧・千仞","—"};
   for(int i=0;i<6;i++){
    float x=30+i*312;bool on=i==4;var rect=new RectangleF(x,850,300,104);
    Nine(g,on?active:disabled,rect,28);
    Text(g,moves[i],i==4?33:35,on?paper:dim,new RectangleF(x+22,857,i==5?256:200,90),i==5);
    if(i<5) {
     using(var br=new SolidBrush(Color.FromArgb(on?240:150,23,44,52)))g.FillRectangle(br,x+218,879,68,45);
     Text(g,"快",32,on?C("#B2A3EB"):C("#787283"),new RectangleF(x+218,880,68,44),true);
    }
   }
   string[] cmds={"守勢","調息","道具","逃跑"};
   for(int i=0;i<4;i++){float x=966+i*234;Nine(g,disabled,new RectangleF(x,964,222,92),28);Text(g,cmds[i],36,dim,new RectangleF(x,964,222,92),true);}
   using(var br=new SolidBrush(Color.FromArgb(225,23,44,52)))g.FillRectangle(br,30,981,142,59);
   using(var pen=new Pen(C("#B89A66"),2))g.DrawRectangle(pen,30,981,142,59);
   Text(g,"沈清禾",36,C("#F3D58E"),new RectangleF(30,981,142,59),true);
   Save(b,"preview/battle_ui_1920x1080.png");
   var ep=new EncoderParameters(1);ep.Param[0]=new EncoderParameter(System.Drawing.Imaging.Encoder.Quality,88L);
   var enc=Array.Find(ImageCodecInfo.GetImageEncoders(),x=>x.MimeType=="image/jpeg");
   b.Save(Path.Combine(output,"preview/battle_ui_1920x1080.jpg"),enc,ep);ep.Dispose();
  }
 }
 static void Sheet() {
  using(var b=new Bitmap(1440,620,PixelFormat.Format32bppArgb))
  using(var g=G(b)) {
   g.Clear(C("#172C34"));Color paper=C("#EAE3CF"),dim=C("#AAD0C3");
   Text(g,"戰鬥介面 · 批次 1",38,paper,new RectangleF(50,28,1300,60));
   string[] bn={"button","button_disabled","button_pressed","button_active"},bl={"一般（既有）","停用","按下","可操作"};
   for(int i=0;i<4;i++){
    string p=i==0?Path.Combine(input,"button.png"):Path.Combine(output,"ui/"+bn[i]+".png");
    using(var img=Load(p))g.DrawImage(img,new RectangleF(45+i*350,130,300,120));
    Text(g,bl[i],27,paper,new RectangleF(45+i*350,258,300,40),true);
   }
   Text(g,"內力 · 霧玉青",27,dim,new RectangleF(55,335,380,40));
   Text(g,"行動 / 蓄招 · 舊金",27,dim,new RectangleF(760,335,500,40));
   foreach(float ratio in new float[]{1f,.5f,.1f}) {
    int n=ratio==1?0:ratio==.5f?1:2;
    DrawBar(g,"ui/mp_track.png","ui/mp_fill.png",new RectangleF(55,405+n*52,550,26),ratio);
    DrawBar(g,"ui/gauge_track.png","ui/gauge_fill.png",new RectangleF(760,405+n*52,550,26),ratio);
   }
   Text(g,"勁路與狀態僅保留文字標籤",23,dim,new RectangleF(55,565,1300,40));
   Save(b,"preview/components_1440x620.png");
  }
 }
 public static void Run(string source,string dest) {
  input=source;output=dest;Directory.CreateDirectory(output);
  using(var atlas=Load(Path.Combine(input,"ui-generated.png"))){Buttons(atlas);Bars(atlas);}
  Preview();Sheet();
 }
}

