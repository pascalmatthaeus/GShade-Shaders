/*
Filmic Anamorph Sharpen PS v1.3.0 (c) 2018 Jacob Maximilian Fober

This work is licensed under the Creative Commons 
Attribution-ShareAlike 4.0 International License. 
To view a copy of this license, visit 
http://creativecommons.org/licenses/by-sa/4.0/.
*/
// Lightly optimized by Marot Satil for the GShade project.


	  ////////////
	 /// MENU ///
	////////////

uniform float Strength <
	ui_label = "Sharpen strength";
	ui_type = "slider";
	ui_min = 0.0; ui_max = 100.0; ui_step = 0.01;
> = 60.0;

uniform int Coefficient <
	ui_tooltip = "For digital video signal use BT.709, for analog (like VGA) use BT.601";
		ui_label = "YUV coefficients";
		ui_type = "radio";
		ui_items = "BT.709 - digital\0BT.601 - analog\0";
> = 0;

uniform float Clamp <
	ui_label = "Sharpen clamping";
	ui_type = "slider";
	ui_min = 0.5; ui_max = 1.0; ui_step = 0.001;
> = 0.65;

uniform float Offset <
	ui_label = "High-pass offset";
	ui_tooltip = "High-pass cross offset in pixels";
	ui_type = "slider";
	ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
> = 0.1;

uniform int Contrast <
	ui_label = "Enable edges masking";
	ui_tooltip = "Depth high-pass mask switch";
	ui_tooltip = "Depth high-pass mask amount";
	ui_type = "slider";
	ui_min = 0; ui_max = 2000; ui_step = 1;
> = 128;

uniform bool Preview <
	ui_label = "Preview sharpen layer";
	ui_tooltip = "Preview sharpen layer and mask for adjustment.\n"
		"If you don't see red strokes,\n"
		"try changing Preprocessor Definitions in the Settings tab.";
	ui_category = "Debug View";
> = false;


	  //////////////
	 /// SHADER ///
	//////////////

#include "ReShade.fxh"

// RGB to YUV709 Luma
static const float3 Luma709 = float3(0.2126, 0.7152, 0.0722);
// RGB to YUV601 Luma
static const float3 Luma601 = float3(0.299, 0.587, 0.114);

// Overlay blending mode
float Overlay(float LayerA, float LayerB)
{
	const float MinA = min(LayerA, 0.5);
	const float MinB = min(LayerB, 0.5);
	const float MaxA = max(LayerA, 0.5);
	const float MaxB = max(LayerB, 0.5);
	return 2.0 * (MinA * MinB + MaxA + MaxB - MaxA * MaxB) - 1.5;
}

// Sharpen pass
float3 FilmicAnamorphSharpenPS(float4 vois : SV_Position, float2 UvCoord : TexCoord) : SV_Target
{
	float2 Pixel = ReShade::PixelSize;

	// Choose luma coefficient, if False BT.709 luma, else BT.601 luma
	const float3 LumaCoefficient = bool(Coefficient) ? Luma601 : Luma709;

	if(Contrast)
	{
		float2 DepthPixel = Pixel * Offset + Pixel;
		Pixel *= Offset;
		// Sample display image
		const float3 Source = tex2D(ReShade::BackBuffer, UvCoord).rgb;
		// Sample display depth image
		const float SourceDepth = ReShade::GetLinearizedDepth(UvCoord);

		const float2 NorSouWesEst[4] = {
			float2(UvCoord.x, UvCoord.y + Pixel.y),
			float2(UvCoord.x, UvCoord.y - Pixel.y),
			float2(UvCoord.x + Pixel.x, UvCoord.y),
			float2(UvCoord.x - Pixel.x, UvCoord.y)
		};

		const float2 DepthNorSouWesEst[4] = {
			float2(UvCoord.x, UvCoord.y + DepthPixel.y),
			float2(UvCoord.x, UvCoord.y - DepthPixel.y),
			float2(UvCoord.x + DepthPixel.x, UvCoord.y),
			float2(UvCoord.x - DepthPixel.x, UvCoord.y)
		};

		// Luma high-pass color
		// Luma high-pass depth
		float HighPassColor = 0.0, Contrast = 0.0;
	
		[loop]
		for(int s = 0; s < 4; s++)
		{
			HighPassColor += dot(tex2D(ReShade::BackBuffer, NorSouWesEst[s]).rgb, LumaCoefficient);
			Contrast += ReShade::GetLinearizedDepth(NorSouWesEst[s])
			+ ReShade::GetLinearizedDepth(DepthNorSouWesEst[s]);
		}

		HighPassColor = 0.5 - 0.5 * (HighPassColor * 0.25 - dot(Source, LumaCoefficient));

		Contrast = 1.0 - Contrast * 0.125 + SourceDepth;
		Contrast = min(1.0, Contrast) + 1.0 - max(1.0, Contrast);
		Contrast = saturate(Contrast * Contrast + 1.0 - Contrast);

		// Sharpen strength
		HighPassColor = lerp(0.5, HighPassColor, Strength * Contrast);

		// Clamping sharpen
		HighPassColor = (Clamp != 1.0) ? max(min(HighPassColor, Clamp), 1.0 - Clamp) : HighPassColor;

		const float3 Sharpen = float3(
			Overlay(Source.r, HighPassColor),
			Overlay(Source.g, HighPassColor),
			Overlay(Source.b, HighPassColor)
		);

		if(Preview) // Preview mode ON
		{
			const float PreviewChannel = lerp(HighPassColor, HighPassColor * Contrast, 0.5);
			return float3(
				1.0 - Contrast * (1.0 - HighPassColor), 
				PreviewChannel, 
				PreviewChannel
			);
		}

		return Sharpen;
	}
	else
	{
		Pixel *= Offset;

		// Sample display image
		const float3 Source = tex2D(ReShade::BackBuffer, UvCoord).rgb;
	
		const float2 NorSouWesEst[4] = {
			float2(UvCoord.x, UvCoord.y + Pixel.y),
			float2(UvCoord.x, UvCoord.y - Pixel.y),
			float2(UvCoord.x + Pixel.x, UvCoord.y),
			float2(UvCoord.x - Pixel.x, UvCoord.y)
		};

		// Luma high-pass color
		float HighPassColor = 0.0;
		[loop]
		for(int s = 0; s < 4; s++) HighPassColor += dot(tex2D(ReShade::BackBuffer, NorSouWesEst[s]).rgb, LumaCoefficient);
		HighPassColor = 0.5 - 0.5 * (HighPassColor * 0.25 - dot(Source, LumaCoefficient));

		// Sharpen strength
		HighPassColor = lerp(0.5, HighPassColor, Strength);

		// Clamping sharpen
		HighPassColor = (Clamp != 1.0) ? max(min(HighPassColor, Clamp), 1.0 - Clamp) : HighPassColor;

		const float3 Sharpen = float3(
			Overlay(Source.r, HighPassColor),
			Overlay(Source.g, HighPassColor),
			Overlay(Source.b, HighPassColor)
		);

		// Preview mode ON
		return Preview ? HighPassColor : Sharpen;
	}
}


	  //////////////
	 /// OUTPUT ///
	//////////////

technique FilmicAnamorphSharpen < ui_label = "Filmic Anamorphic Sharpen"; >
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = FilmicAnamorphSharpenPS;
	}
}
