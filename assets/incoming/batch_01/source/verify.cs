using System; using System.IO; using System.Drawing;
public class UiMetrics { public string Path; public int Width,Height,Transparent,Opaque,AlphaDifferences,NonIdentifierColors; public int[] BBox; public bool CornersClear; }
public static class UiVerify {
 public static UiMetrics[] Run(string root,string original) {
 string[] files={"ui/button_disabled.png","ui/button_pressed.png","ui/button_active.png","ui/mp_track.png","ui/mp_fill.png","ui/gauge_track.png","ui/gauge_fill.png"};
 var list=new UiMetrics[files.Length];
 using(var normal=new Bitmap(original))for(int i=0;i<files.Length;i++)using(var b=new Bitmap(System.IO.Path.Combine(root,files[i]))) {
 var m=new UiMetrics();m.Path=files[i];m.Width=b.Width;m.Height=b.Height;int l=b.Width,t=b.Height,r=0,bt=0;
 for(int y=0;y<b.Height;y++)for(int x=0;x<b.Width;x++){
 var c=b.GetPixel(x,y);if(c.A==0)m.Transparent++;else{l=Math.Min(l,x);t=Math.Min(t,y);r=Math.Max(r,x);bt=Math.Max(bt,y);}if(c.A==255)m.Opaque++;
 if(i<3 && c.A!=normal.GetPixel(x,y).A)m.AlphaDifferences++;
 }
 m.BBox=new int[]{l,t,r+1,bt+1};m.CornersClear=b.GetPixel(0,0).A==0 && b.GetPixel(b.Width-1,0).A==0 && b.GetPixel(0,b.Height-1).A==0 && b.GetPixel(b.Width-1,b.Height-1).A==0;
 int ew=i<3?320:384,eh=i<3?128:20;
 if(m.Width!=ew ||m.Height!=eh ||!m.CornersClear ||m.AlphaDifferences!=0 ||m.NonIdentifierColors!=0 ||m.Transparent==0 ||m.Opaque==0)throw new Exception("Invalid asset "+files[i]);
 if((i==4 ||i==6) &&(m.BBox[0]<10 || m.BBox[2]>374))throw new Exception("Fill margins "+files[i]);
 list[i]=m;
 }return list;
 }
}
